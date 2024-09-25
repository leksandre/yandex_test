#!/usr/bin/perl

# чтобы не возникало проблем с локалью utf8
#use locale;

use POSIX;
use strict;
use Time::HiRes;
use Socket;
use Sys::Hostname;
use Fcntl;
use FileHandle;
use Symbol;


use vars qw(
$proto $pid $GLOBAL_TIME $hispaddr $inmask $CHILDREN_COUNT $CHILDREN_PID
$paddr $self
%CONF
%CHILDREN
);

%CONF = ();
%CHILDREN = (); # Ключами являются текущие идентификаторы процессов-потомков 

$CHILDREN_COUNT = 0; # Текущее число потомков
$CHILDREN_PID = 0;
$CONF{'CONFIGFILE'} = '/home/grifon/Grifon/etc/grifon.conf';
$CONF{'DEBUGMODE'} = 1;
$CONF{'V'} = 'Grifon/0.01';

(undef, $self) = $0 =~ m#^(.*)/(.*)#o;


my $data_send;
for(@ARGV){$data_send .= $_." ";}
if ($data_send) 
{
	$data_send =~ s/^\s+//;
	$data_send =~ s/\s+$//;
	$data_send .= " ";
	my $mess = <<HELP;
Usage: $self [-f file]
               [-v] [-V] [-h] [-d]
Options:
  -f file          : specify an alternate ServerConfigFile
  -v               : show version number
  -V               : show compile settings
  -h               : list available command line options (this page)
  -d               : Print debugging information.
HELP
	if ($data_send =~ /-h|--help/) {
		print(STDOUT $mess);
		exit;
	} elsif ($data_send =~ /-v/){
		print(STDOUT 'Server version: '.$CONF{'V'});
		exit;
	} 
	elsif ($data_send =~ /-f\s*(.*?)\s*/){ $CONF{'CONFIGFILE'} = $1; }
	elsif ($data_send =~ /-d\s*/){ $CONF{'DEBUGMODE'} = 1; }
	else {
		print(STDOUT $self.': invalid option -- '.$data_send."\n".$mess);
		exit;
	}
}

my($cfg);
open(CONF, "< ".$CONF{'CONFIGFILE'}) || die "Can't open conf ".$CONF{'CONFIGFILE'}.": $!\n";
"" =~ m/()()/;
while( $cfg = <CONF> ) {
	chomp($cfg);
	$cfg =~ s/(^|\s)#.*//o;
	$cfg =~ s/^\s+//o;
	next unless length($cfg);
	if($cfg =~ m/\{([-\w]+)\}/) {
		my($r) = uc($1);
		substr($cfg, index($cfg, ('{'.$1.'}'), 0), length(('{'.$1.'}')), $CONF{$r});
	}
	$cfg =~ /([-\w]+)\s*=\s*\"(.*)\"/;
	next unless ($1 || $2);
	my($k, $v) = ($1, $2);
	$CONF{uc($k)} = $v;
}
close(CONF);

{ # загрузка модулей

	unshift(@INC, $CONF{'ROOTSERVER'});

	my $libpath = $CONF{'MAINLIB'};
	$libpath =~ s#/#::#g;

	# библиотека модулей обработки
	my @ModuleLoad = (
		{ 'mod' => 'Str', 'func' => 'lc uc win2koi' },
		{ 'mod' => 'Utils', 'func' => 'tform2 time_form httptform expire_calc _join _split dform2' },
		{ 'mod' => 'DB', 'func' => 'Open_DB Close_DB' },
		{ 'mod' => 'Cgi', 'func' => 'escape unescape param' },
		{ 'mod' => 'Status', 'func' => '' },
		{ 'mod' => 'http', 'func' => '' },
		{ 'mod' => 'Handler', 'func' => '' }
	);
	my $mnemonicCode = '';

	foreach my $n (@ModuleLoad) {
		# создаем мнимый код загрузки модулей
		$mnemonicCode .= 'use '.$libpath.'::'.$n->{'mod'}.' qw('.$n->{'func'}.');'."\n";
	}

	# warn $mnemonicCode; # возможно понадобится
	eval $mnemonicCode; # обрабатываем только один раз, для скорости
	die($@."\n") if $@;

}
chdir($CONF{'SERVERROOT'}) || die "Couldn't change dir to ".$CONF{'SERVERROOT'}.": $!\n";


# Установить обработчики сигналов.
$SIG{INT} = $SIG{TERM} = $SIG{__DIE__} = \&HUNTSMAN;
$SIG{PIPE} = 'IGNORE';

unless ($CONF{'DEBUGMODE'}) {
	STDOUT->autoflush(1);
	STDERR->autoflush(1);
}

$pid = fork unless ($CONF{'DEBUGMODE'});

unless ($CONF{'DEBUGMODE'}) {
	print (STDOUT "HTTP daemon ".$CONF{'V'}." .... Started..\n") if $pid;
	exit if $pid;
	die "Couldn't fork: $!\n" unless defined($pid);
	# Стать лидером группы:
	$pid = POSIX::setsid() or die "Can't start a new session\n";
	open (PID, "> ".$CONF{'PIDDIR'}.'/'.$CONF{'PIDFILE'});
	flock(PID, 2);
	print PID $pid;
	close (PID);
	# Полностью отсоединиться от терминалки
	close(STDOUT);
	close(STDERR);
	close(STDIN);
	open (STDERR, ">> ".$CONF{'LOGDIR'}."/".$CONF{'RADIUSLOG'}.'1') || die "Can't reopen STDOUT: $!\n";
	open (STDOUT, ">> ".$CONF{'LOGDIR'}."/".$CONF{'RADIUSLOG'}.'2') || die "Can't reopen STDOUT: $!\n";
}


$GLOBAL_TIME = time();
$proto = getprotobyname('tcp');
$CONF{'PORTHTTPD'} = getservbyname('http', 'tcp') if (!$CONF{'PORTHTTPD'});
	die "Could not find httpd port port" if (!$CONF{'PORTHTTPD'});


if ($CONF{'INTERFACE'} && $CONF{'INTERFACE'} =~ m/^\d+\.\d+\.\d+\.\d+$/) {
	$paddr = sockaddr_in($CONF{'PORTHTTPD'}, inet_aton($CONF{'INTERFACE'}));
} else {
	$paddr = sockaddr_in($CONF{'PORTHTTPD'}, INADDR_ANY);

}


socket(HTTPD, PF_INET, SOCK_STREAM, $proto) || die "auth socket: $!";
setsockopt(HTTPD, SOL_SOCKET, SO_REUSEADDR, 1);
bind(HTTPD, $paddr) || die "httpd bind: $!";
LOG('HTTPD socket ('.$CONF{'PORTHTTPD'}.') bind OK');
listen(HTTPD, SOMAXCONN);

my $server_flags = fcntl(HTTPD, F_SETFL, 0);
fcntl(HTTPD, F_SETFL, $server_flags | O_NONBLOCK);

$inmask = '';
vec($inmask, fileno(HTTPD), 1) = 1;

#$| = 1;

$SIG{CHLD} = \&REAPER;
sub REAPER { # Чистка мертвых потомков
	my $pid = wait;
	$CHILDREN_COUNT--;
	delete $CHILDREN{$pid};
	LOG('Child pid="'.$pid.'" is dead. Birth of the new child.');
}

sub HUNTSMAN { # Обработчик сигнала SIGINT
	my($signal) = shift;
	LOG('Signal: '.$signal.'. I kill all children...');
	local($SIG{CHLD}) = 'ignore'; # Убиваем своих потомков
	kill 'INT' => keys %CHILDREN;
	if ($signal) {
		open(PID,"> ".$CONF{'PIDDIR'}.'/'.$CONF{'PIDFILE'});
		close(PID);
		LOG('Stoped');
		exit; # Корректно завершиться 
	} else {
		LOG('Signal: '.$signal.'ignore');
	}
}
# Создать потомков.
for (1 .. $CONF{'PREFORK'}) {
	make_new_child();
}


# Поддерживать численность процессов,
while (1) {
	my($i);
	sleep; # Ждать сигнала (например, смерти потомка).
	while (waitpid(-1, WNOHANG) > 0) { $CHILDREN_COUNT--; };
# 	$CHILDREN_COUNT-- until ( waitpid(-1, WNOHANG) == -1);
	$CHILDREN_COUNT = 0 if $CHILDREN_COUNT<0;
	for ($i = $CHILDREN_COUNT; $i < $CONF{'PREFORK'}; $i++) {
		make_new_child(); # Заполнить пул потомков.
	}
}

sub make_new_child {
	my($pid, $sigset);

	# Блокировать сигнал для fork.
	$sigset = POSIX::SigSet->new(SIGINT);
	sigprocmask(SIG_BLOCK, $sigset) or die "Can't block SIGINT for fork: $!\n";
	die "fork: $!" unless defined ($pid = fork);
	if ($pid) {
	# Родитель запоминает рождение потомка и возвращается,
		sigprocmask(SIG_UNBLOCK, $sigset) or die "Can't unblock SIGINT for fork: $!\n";
		$CHILDREN{$pid} = 1;
		$CHILDREN_COUNT++;
		return;
	} else {
		# Потомок *не может* выйти из этой подпрограммы.
		$SIG{INT} = $SIG{TERM} = $SIG{__DIE__} = \&CHILDREN_SIGNAL_HANDLE; # Пусть sigint убивает процесс, как это было раньше.
		$SIG{CHLD} = "IGNORE";

		# Разблокировать сигналы
		sigprocmask(SIG_UNBLOCK, $sigset) or die "Can't unblock SIGINT for fork: $!\n";

		# Обрабатывать подключения, пока их число не достигнет $MAX_CLIENTS_PER_CHILD.
		$CHILDREN_PID = POSIX::setsid() or die "Can't start a new session\n";
		LOG("I was born!");

		my($CLIENT_COUNT) = 0;
REQ:
		while ($CLIENT_COUNT< $CONF{'MAX_CLIENTS_PER_CHILD'}) {
#print $CONF{'INTERFACE'}."\n";
			my $s = select(my $outmask = $inmask, undef, undef, 1);
			if ($s > 0 && accept(CLIENT, HTTPD)) {
				$CLIENT_COUNT++;

				# включить неблокирующий режим для клиента
				my($client_flags) = '';
				$client_flags = fcntl(CLIENT, F_GETFL, 0) || die "Can`t get flags for socket: $!\n";
				fcntl(CLIENT, F_SETFL, $client_flags | O_NONBLOCK) || die "Can`t make socket nondlocking: $!\n";

				my ($client) = \*CLIENT; # получить ссылку на объект glob для идентификации клиента
				new_http_client($client); # инициализация обработчика http запросов
				my $client_inmask = '';
				vec($client_inmask, fileno(CLIENT), 1) = 1; # упаковать в вектор клиента
				my $indata = ''; # буфер чтения
				my $outdata = ''; # буфер вывода
				my $htype = ''; # тип обработки
				my $status = undef(); # статус запроса
				my $retour = undef(); # проверяем состояние клиента
				my $hand = undef(); # флаг обработки данных

				# цикл чтения данных
				while (1) {

					# если есть с чем работать
					#select(my $client_outmask = $client_inmask, $client_inmask, undef, 0);

					# проверяем возможность чтения
					$retour = select(my $client_outmask = $client_inmask, undef, undef, 0.005);
					if ($retour > 0 && !$status ) {

						my $data = '';
						my $rv = recv(CLIENT, $data, POSIX::BUFSIZ, 0);

						unless (defined($rv) && length($data)) {
						# закрыть клиента
							del_http_client($client);
							$client_inmask = '';
							$outdata = '';
							$client = '';
							close(CLIENT);
							next REQ;
						}
						$indata .= $data;
						$status = get_request($client, \$indata);

						# проверка на таймаут
						$status = timeout_http_client($client) unless ($status);

						# продолжить чтение если запрос не готов и нет ошибок
						next unless ($status);
					}

					# обработка запроса
					if ( $status && !$hand ) {
						if ($status == 200) {

						# определить ip хоста
							my $other_end = getpeername(CLIENT) or die "Couldn't identify other end: $!\n";
							my ($port, $iaddr) = unpack_sockaddr_in($other_end);
							my $ip_address = inet_ntoa($iaddr);

							$htype = process_http_request($client, $ip_address, $hispaddr, \$outdata);
							if ($htype) {
								# запрос успешно обработан
								$outdata = get_header($client, 5, length($outdata)).$outdata;
							} else {
								# запрос обработан хреново
								$outdata = send_error($client, 404);
							}
						} else {
							$outdata = send_error($client, $status);
						}
						$hand = 1;
					}


					# проверка возможности записи
					$retour = select(undef, my $client_outmask = $client_inmask, undef, 0.005);
					if ( $retour > 0  && $hand && length($outdata) ) {
						my $lenwrite = 0;
						$lenwrite = send(CLIENT, $outdata, 0);
						substr($outdata, 0, $lenwrite) = '';
					}

					# если больше нечего записывать, закрыть клиента
					if ($hand && !length($outdata)) {
						del_http_client($client);
						$client_inmask = '';
						$outdata = '';
						$client = '';
						close(CLIENT);
						next REQ;
					}
				}
			}
		}
		LOG("MAX CLIENTS Handled! I finish work.");
		CHILDREN_SIGNAL_HANDLE('exit');
	}
}

sub CHILDREN_SIGNAL_HANDLE  {
	my($signal) = shift;
	LOG("Me have killed!");
	close(HTTPD);
	exit; # Корректно завершиться 
}

sub LOG {
	return unless ($CONF{'LOGLEVEL'});
	my($mes) = $_[0];
	my($time) = scalar(localtime);
	my($ident) = $CHILDREN_PID ? 'Child pid="'.$CHILDREN_PID.'": ' : 'Main: ';
	if ($CONF{'DEBUGMODE'}) {
		print STDOUT $time.': '.$ident.$mes."\n";
	} else {
		open (LOG, ">> ".$CONF{'LOGDIR'}."/".$CONF{'RADIUSLOG'}) || die ("Can`t open log file $!");
		print LOG $time.': '.$ident.$mes."\n";
		close LOG;
	}
}


1;
