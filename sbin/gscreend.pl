#!/usr/bin/perl

use utf8;
use strict;
use POSIX;


use vars qw(
$filePath $videoPath $lastReloadPlayList $bannerPath $lastDBconnect
$playVideoFile $widgets $playList $lastReloadNets $MPLAYER
%CONF
%PARAM
);


use Glib qw(TRUE FALSE);
use Gtk2;
use Text::Iconv;
use FileHandle;


$lastReloadNets = time();
$lastReloadPlayList = time();
$widgets = {};
$CONF{'CONFIGFILE'} = '/home/grifon/Grifon/etc/grifon.conf';
%PARAM = ();
$MPLAYER = undef();

use constant DB_RECHECK => 10; #сек.


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
	$cfg =~ /([-\w]+)\s*=\s*\"(.+)\"/;
	next unless ($1 || $2);
	my($k, $v) = ($1, $2);
	$CONF{uc($k)} = $v;
}
close(CONF);

# грузим модули
{
	unshift(@INC, $CONF{'ROOTSERVER'});

	my $libpath = $CONF{'MAINLIB'};
	$libpath =~ s#/#::#g;

	# библиотека модулей обработки
	my @ModuleLoad = (
		{ 'mod' => 'Str', 'func' => 'lc uc' },
		{ 'mod' => 'Utils', 'func' => 'tform2 time_form httptform expire_calc _join _split dform2' },
		{ 'mod' => 'DB', 'func' => 'Open_DB Close_DB' },
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
$filePath = $CONF{'GSCREENFILESDIR'};
$videoPath = $CONF{'HTDOCSDIR'}.$CONF{'VIDEODIR'};
$bannerPath = $CONF{'HTDOCSDIR'}.$CONF{'BANNERSDIR'};
$playVideoFile = { 'file_id' => 0, 'suf' => '' };


reload_param ();
reload_playlist ();


my $timeout_id = undef;
my $lastTime1 = (time()-10);
my $lastTime2 = (time()-10);
my $lastTime3 = (time()-100);
my $lastImg = 1;

sleep(3);

start_gscreen (1);


sub start_gscreen {
	my $is_first = shift;
	my $count = 0;
	 if ( $widgets->{'banner1_plug'} ) {
		$timeout_id=undef();
		$widgets = undef();
		Gtk2->main_quit;
	}
	while ( $is_first || !pid_check() ) {
		$count++;
		# запуск процесса gscreen
		system( $CONF{'GSCREEN'}." > /dev/null 2>&1 &") 
			if ( $count == 1 );
		sleep(1);
		reload_param ();
		my $check = pid_check();
		die "exec error\n" if ( $count > 10 && !$check );
		if ( $check ) {
			init_plug();
			last;
		}
	}
}


sub init_plug {

#	$MPLAYER = start_mplayer();
	load_mplayer();

#	$widgets->{'banner2_plug'}->hide_all if ( exists $widgets->{'banner2_plug'} );
#	$widgets->{'video_plug'}->hide_all if ( exists $widgets->{'video_plug'} );
#	Gtk2->main_quit if ( exists $widgets->{'banner1_plug'} );
	Gtk2->init;
	$timeout_id = Glib::Timeout->add (1000, \&timeout);

	# первый баннер
#	$widgets->{'banner1_plug'}->destroy;
	$widgets->{'banner1_plug'} = undef;
	$widgets->{'banner1_plug'} = Gtk2::Plug->new($PARAM{'banner1_wid'}->{'arg'});
	$widgets->{'banner1_img'} = new Gtk2::Image ( );
	$widgets->{'banner1_plug'}->add( $widgets->{'banner1_img'} );
	$widgets->{'banner1_plug'}->show_all;

	# второй баннер
	$widgets->{'banner2_plug'} = undef;
	$widgets->{'banner2_plug'} = Gtk2::Plug->new($PARAM{'banner2_wid'}->{'arg'});
	$widgets->{'banner2_img'} = new Gtk2::Image();
	$widgets->{'banner2_plug'}->add( $widgets->{'banner2_img'} );
	$widgets->{'banner2_plug'}->show_all;

	# видео фрейм
	$widgets->{'video_plug'} = undef;
	$widgets->{'video_plug'} = Gtk2::Plug->new( $PARAM{'video_wid'}->{'arg'} );
	$widgets->{'video_img'} = new Gtk2::Image();
	$widgets->{'video_plug'}->add( $widgets->{'video_img'} );
	
	Gtk2->main;
}


sub timeout {
#	$banner1_img->queue_draw;

	my $time = time();
	unless ( pid_check() ) {
		sleep(2);
		start_gscreen ();
		return FALSE;
	}

	reload_playlist() if ( dform2($lastReloadPlayList) ne dform2(time) );

	if ( ($time - $lastDBconnect) > DB_RECHECK ) {
		reload_param ();
		reloadNets ();
	}


	my %bfile_id = get_file('banner');
#	$widgets->{'banner1_img'}->set_from_file( $bannerPath.'/'.$bfile_id{'file_id'}.'.'.$bfile_id{'suf'} );
	my $b1_filepath = $bannerPath.'/'.$bfile_id{'file_id'}.'.'.$bfile_id{'suf'};
	my $b1_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_scale ($b1_filepath, 400, 117, 0);
	$widgets->{'banner1_img'}->set_from_pixbuf ($b1_pixbuf);
#	$CHANNELS->{$rid}->{'data'}->{'logo'} = Gtk2::Gdk::Pixbuf->new_from_file_at_scale ($LogoFile, LOGO_SIZE, LOGO_SIZE, 0);


	if ( ($time-$lastTime2) > 10 ) {
		$widgets->{'banner2_img'}->set_from_file( $filePath.'/'.'weather.png' );
		$lastTime2 = time();
	}

	# выводим видео
#	my $suf = $playVideoFile->{'suf'};
#	if ( $suf eq 'avi' || $suf eq 'wmv' || $suf eq 'mpg' ) {
#		$widgets->{'video_plug'}->hide_all if ( exists $widgets->{'video_plug'} );
#	}
	my %vfile_id = get_file('video');
#print $vfile_id{'file_id'}.'.'.$vfile_id{'suf'}."\n";

	if ( 
			$playVideoFile->{'file_id'} != $vfile_id{'file_id'}
			|| $playVideoFile->{'suf'} ne $vfile_id{'suf'} ) {

		$playVideoFile->{'file_id'} = $vfile_id{'file_id'};
		$playVideoFile->{'suf'} = $vfile_id{'suf'};
		my ($base, $suf) = ($vfile_id{'file_id'}, $vfile_id{'suf'});

		my $file = $base.'.'.$suf;
		next unless ($suf =~ m/^(avi|wmv|mpg|jpg|gif|png|mov)$/io);

		stop_mplayer();
#		system("killall -9 mplayer > /dev/null 2>&1 &");	
		if ( $suf eq 'jpg' || $suf eq 'gif' || $suf eq 'png' ) {
			$widgets->{'video_img'}->set_from_file( $videoPath.'/'.$file );
			$widgets->{'video_plug'}->show_all;
		} else {
#			my $str = sprintf(
#				"/usr/bin/mplayer -vf scale=%d:%d %s -wid %d ".$videoPath.'/'.$file." > /dev/null 2>&1 &",
#						$PARAM{'video_width'}->{'arg'},
#						$PARAM{'video_height'}->{'arg'},
#						( $vfile_id{'offset'} == 0 ? '' : '-ss '.$vfile_id{'offset'} ),
#						$PARAM{'video_wid'}->{'arg'}
#					);
#			system( $str );
#			stop_mplayer($MPLAYER);
			load_mplayer($videoPath.'/'.$file);
			jump_mplayer($vfile_id{'offset'}) if $vfile_id{'offset'} != 0;
			$widgets->{'video_plug'}->hide_all if ( exists $widgets->{'video_plug'} );
		}
		$lastTime3 = time();
	}
	return TRUE;
}



sub reload_playlist {
	my ($sql, $sth);
	
	my @startDate = split('\.', dform2(time()));
	my $now_time = mktime(0, 0, 0, $startDate[0], ($startDate[1]-1), ($startDate[2]-1900) );
	$playList = {};
	
	my $DBH = Open_DB ($CONF{'DBNAME'}, $CONF{'DBHOST'}, $CONF{'DBUSER'}, $CONF{'DBPASS'});
	$sql = sprintf(
"select playlist_id, start_time, stop_time, orders, form
from playlist
where start_ut<=%d
and stop_ut>=%d
and is_deleted=0",
$now_time, $now_time
);

	$sth = $DBH->prepare($sql);
	$sth->execute();
	while ( my($playlist_id, $start_time, $stop_time, $orders, $form) = $sth->fetchrow_array() ) {
		$playList->{$form}->{ $playlist_id } = {
							'orders' => $orders,
							'playlist_id' => $playlist_id,
							'start_time' => $start_time,
							'stop_time' => $stop_time,
							'content_time' => 0,
							'files' => {}
						};
	}
	$sth->finish();


	my @pls = ();
	foreach my $form ( keys %{$playList} ) {
		push(@pls, keys %{$playList->{$form}} );
	}
	my $pls = join(' or playlist_items.playlist_id=', @pls);

	$sql = sprintf(
"select 
playlist_items.items_id,
playlist_items.playlist_id,
playlist_items.time_start,
playlist_items.file_id,
playlist_items.chrono,
playlist_items.orders,
playlist.form,
files.suf
from playlist_items
join files
join playlist
where playlist_items.is_deleted=0 
and playlist.playlist_id=playlist_items.playlist_id
and playlist_items.file_id=files.file_id
and ( playlist_items.playlist_id=%s ) order by playlist_items.orders asc", 
 ( length($pls) == 0 ? 0 : $pls) );
	$sth = $DBH->prepare($sql);
	$sth->execute();
	while ( my($items_id, $playlist_id, $time_start, $file_id, $chrono, $orders, $form, $suf) = $sth->fetchrow_array() ) {
		$playList->{$form}->{ $playlist_id }->{'files'}->{$items_id} =
				{
					'file_id' => $file_id,
					'time_start' => $time_start,
					'chrono' => $chrono,
					'orders' => $orders,
					'suf' => $suf,
					'offset' => 0,
					'cntTime' => 0
				};
		$playList->{$form}->{ $playlist_id }->{'content_time'} = $time_start+$chrono;
	}
	$sth->finish();
	$lastReloadPlayList = time();
	Close_DB ($DBH);
	$lastDBconnect = time();
}

sub get_file {
	my $form = shift;
	my %NULL = ( 'file_id' => 0, 'suf' => 'png' );
	my $time = time2sec(sprintf("%d:%d:%d", (localtime(time()))[2,1,0]));
	return %NULL unless exists $playList->{$form};
	my %PL = %{$playList->{$form}};
PL_SEARCH:
	foreach my $playlist_id ( sort { $PL{$a}->{'orders'} <=> $PL{$b}->{'orders'} } keys %PL ) {
		if ( $time >= $PL{$playlist_id}->{'start_time'}
			&&  $time < $PL{$playlist_id}->{'stop_time'} ) {
			my %FL = %{$PL{$playlist_id}->{'files'}};
			foreach my $items_id ( sort { $FL{$a}->{'orders'} <=> $FL{$b}->{'orders'} } keys %FL ) {
				my $cntTime = $PL{$playlist_id}->{'content_time'}
						* int ( ( $time - $PL{$playlist_id}->{'start_time'} )
						/ $PL{$playlist_id}->{'content_time'} )   ;
				$cntTime = $time - $PL{$playlist_id}->{'start_time'} - $cntTime;
				$FL{$items_id}->{'offset'} = $cntTime - $FL{$items_id}->{'time_start'};
				$FL{$items_id}->{'cntTime'} = $cntTime;
				return %{$FL{$items_id}} if ( $FL{$items_id}->{'time_start'} <= $cntTime
						&& ($FL{$items_id}->{'time_start'} + $FL{$items_id}->{'chrono'}) > $cntTime );
			}
		}
	}
	return %NULL;
}


sub pid_check {
	return 0 unless exists $PARAM{'gscreen_pid'}->{'arg'};
	return 0 unless kill(0, $PARAM{'gscreen_pid'}->{'arg'});
	return 1;
}


sub reload_param {
	%PARAM = ();
	my $DBH = Open_DB ($CONF{'DBNAME'}, $CONF{'DBHOST'}, $CONF{'DBUSER'}, $CONF{'DBPASS'});
	my $sth = $DBH->prepare('select param, arg, time from sys_swap');
	$sth->execute();
	while ( my($param, $arg, $time ) = $sth->fetchrow_array() ) {
		$PARAM{$param} = { 'arg' => $arg, 'time' => $time };
	}
	$sth->finish();
	if ( exists $PARAM{'playlist_reload'} ) {
		$sth = $DBH->prepare("delete from sys_swap where param='playlist_reload'");
		$sth->execute();
		$sth->finish();
		reload_playlist();
	}
	Close_DB ($DBH);
	$lastDBconnect = time();
}

sub reloadNets {
	my $time = time();	
	my @date = split(/\./, dform2($time));
	my $reloadTime = mktime(0, 0, 3, $date[0], ($date[1]-1), ($date[2]-1900) );
	if ( $time >= $reloadTime &&  $lastReloadNets < $reloadTime ) {
		my $DBH = Open_DB ($CONF{'DBNAME'}, $CONF{'DBHOST'}, $CONF{'DBUSER'}, $CONF{'DBPASS'});
		my $sth = $DBH->prepare(sprintf("replace into sys_swap (param, arg, time) values ('%s', '%s', %d )",
			'nets_reload', '1', $time ));
		$sth->execute();
		$sth->finish();
		$lastReloadNets = time();
		Close_DB ($DBH);
		$lastDBconnect = time();
	}
}


sub decode_utf8 {
    my $s = shift;
    $s = pack('U0C*', unpack('C*', $s));
    return $s;
}

sub encode_utf8 {
    my $s = shift;
    $s = pack 'C*', unpack 'U0C*', $s;
    return $s;
}

sub time2sec {
	my @t = split(':', shift);
	my $sec = 0;
	$sec = $t[0]*3600 + $t[1]*60 + $t[2]*1 if ( scalar(@t) == 3 );
	$sec = $t[0]*60 + $t[1]*1 if ( scalar(@t) == 2 );
	$sec = $t[0]*1 if ( scalar(@t) == 1 );
	return $sec;
}

sub sec2time {
	my $sec = shift;
	if (!$sec) { $sec = 0; };
	$sec = ( $sec - 86400 ) if ($sec > 86400);
	my $hour = int($sec/3600);
	my $min = int( ($sec-$hour*3600) / 60 );
	$sec = $sec - ($hour*3600+$min*60);
	if ($hour < 10) { $hour = "0".$hour; }
	if ($min < 10) { $min = "0".$min; }
	if ($sec < 10) { $sec = "0".$sec; }
	return $hour.':'.$min.':'.$sec;
}


#sub start_mplayer {
#	my( $args ) = @_;
#	my( $self);
#	
#	system("killall -9 mplayer > /dev/null 2>&1 &");
#	$self = FileHandle->new;
#	my $cmd = sprintf(
#		'|/usr/bin/mplayer -slave -idle -wid %d  1>/dev/null 2>/dev/null',
#		$PARAM{'video_wid'}->{'arg'}
##		$PARAM{'video_width'}->{'arg'},
##		$PARAM{'video_height'}->{'arg'}
#	);
#	$self->open($cmd);
#	return $self;
#}

sub stop_mplayer {
	return unless $MPLAYER;
	$MPLAYER->print("pausing_keep seek 100 1\n");
}


sub load_mplayer {
    my( $file ) = @_;

	if ( $MPLAYER ) {
		$MPLAYER->print("loadfile $file\n");
	} else {
		$MPLAYER = {};
		system("killall -9 mplayer > /dev/null 2>&1 &");
		$MPLAYER = FileHandle->new;
		$MPLAYER->autoflush(1);
		
		my $cmd = sprintf(
			'|/usr/bin/mplayer -slave -osdlevel 0 -idle -zoom -wid %d 1>/dev/null 2>/dev/null',
			$PARAM{'video_wid'}->{'arg'},
#			$PARAM{'video_width'}->{'arg'},
#			$PARAM{'video_height'}->{'arg'}
		);
		$MPLAYER->open($cmd);	
#		$MPLAYER->print("osd 0\n");	
	}

}

sub jump_mplayer {
    my( $seconds ) = @_;
   	return unless $MPLAYER;
    $MPLAYER->print("seek $seconds\n");
}


sub logger {
	my $s = shift;
	open (LOG, ">> encode.log");
	print LOG localtime()." ".$s."\n";
	close(LOG);
}
