#!/usr/bin/perl


use utf8;
use strict;
use POSIX;
use GD;

use vars qw( $widgets $MOVE $CHANNELS $CHANNELS_DATA $PROGRAMMS $sql $sth $TOTAL_CHANNELS $pid
$filePath $lastDBconnect
%PARAM
%CONF
@DoW
@MoY
);


use Glib qw(TRUE FALSE);
use Gtk2::Pango;
use Gtk2 -init;
use Text::Iconv;

$widgets = {};
$MOVE = { 'x-side' => 0, 'x-place' => 0, 'x-place_1' => 0, 'y-side' => 0, 'y-place' => 0 };

%PARAM = ();

$CHANNELS = {};
$CHANNELS_DATA = {};
$PROGRAMMS = {};
$TOTAL_CHANNELS = 0;

$CONF{'CONFIGFILE'} = '/home/grifon/Grifon/etc/grifon.conf';
$CONF{'DEBUGMODE'} = 1;
$CONF{'V'} = 'Grifon/0.01';

$CONF{'back_width'} = '1024';
$CONF{'back_height'} = '768';

$CONF{'progDraw_maxWidth'} = 0;
$CONF{'progDraw_maxheight'} = 0;

@DoW = ("понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресение");
@MoY = ("января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря");
$pid = POSIX::setsid();


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

use constant DB_RECHECK => 10; #сек.

use constant FONT_WIDTH => 15;

use constant PROG_HEIGHT => 55 ;
use constant PROG_FONT => "verdana";
use constant PROG_BORDER => 2;
use constant PROG_FRAME_Y => 492;

use constant PROG_TIME_STEP => 58;
use constant NET_STEP => 300;
use constant CHL_WIDTH => 235;

use constant CONT_TOP_OFFSET => 47;
use constant CONT_LEFT_OFFSET => 42;
use constant VIDEO_LEFT_OFFSET => 455;

use constant BANNER_WIDTH => 400;
use constant BANNER_HEIGHT => 117;
use constant VIDEO_WIDTH => 528;
use constant VIDEO_HEIGHT => 397;

use constant LOGO_SIZE => 40;
use constant LOGO_TOP_offset => 8;
use constant LOGO_RIGHT_offset => 3;

use constant TIMELINE_HEIGHT => 36;

use constant DATE_WIDTH => 46;

$filePath = $CONF{'GSCREENFILESDIR'};



# грузим сетку
nets_reload ();


my $window = Gtk2::Window->new;
$window->signal_connect (delete_event => sub {Gtk2->main_quit; 1});
$window->signal_connect (destroy => \&cleanup_callback);
$window->set_resizable (FALSE);
$window->set_size_request ($CONF{'back_width'}, $CONF{'back_height'});

$window->set_title ("TeleGuide");

$widgets->{'main_table'} = new Gtk2::Table( 1, 1, 0 );

$widgets->{'frame_socket'} = new Gtk2::Socket;
$widgets->{'frame_socket_box'} = new Gtk2::EventBox;
$widgets->{'frame_socket_box'}->set_size_request(VIDEO_WIDTH, VIDEO_HEIGHT);
$widgets->{'frame_socket_box'}->add( $widgets->{'frame_socket'} );

$widgets->{'frame_fixed_video'} = new Gtk2::Fixed();
$widgets->{'frame_fixed_video'}->put( $widgets->{'frame_socket_box'}, VIDEO_LEFT_OFFSET, CONT_TOP_OFFSET );
$widgets->{'main_table'}->attach( $widgets->{'frame_fixed_video'}, 0, 1, 0, 1, [ 'expand', 'fill' ], ['expand', 'fill'], 0, 0 );

# 32 966 392 529


$widgets->{'frame_prog'} = new Gtk2::Fixed();
$widgets->{'frame_prog'}->set_size_request($CONF{'back_width'},0);

$widgets->{'frame_chls'} = new Gtk2::Fixed();
$widgets->{'frame_chls'}->set_size_request($CONF{'back_width'},0);


# нарисовать сетку
$widgets->{'prog_drawArea'} = Gtk2::DrawingArea->new;
$widgets->{'prog_drawArea'}->set_size_request( ($CONF{'back_width'} - CHL_WIDTH), ($CONF{'back_height'} - PROG_FRAME_Y) );
$widgets->{'frame_prog'} = new Gtk2::Fixed();
$widgets->{'frame_prog'}->set_size_request( ($CONF{'back_width'} - CHL_WIDTH),($CONF{'back_height'} - PROG_FRAME_Y) );
$widgets->{'frame_prog'}->put( $widgets->{'prog_drawArea'}, 0, 0 );


# текст для времени программы
$widgets->{'prog_context_time'} = $widgets->{'prog_drawArea'}->create_pango_context;
$widgets->{'prog_layout_time'} = Gtk2::Pango::Layout->new ( $widgets->{'prog_context_time'} );
$widgets->{'prog_layout_desc_time'} = Gtk2::Pango::FontDescription->from_string ("verdana normal 23px");
$widgets->{'prog_layout_time'}->set_font_description ( $widgets->{'prog_layout_desc_time'} );
#$widgets->{'prog_layout_time_color1'} = Gtk2::Gdk::Color->new (0x0000, 0x5999, 0xb555);
#$widgets->{'prog_layout_time_color2'} = Gtk2::Gdk::Color->new (0x6999, 0xaddd, 0xf333);


#$widgets->{'prog_layout_time'}->set_font_description ($widgets->{'prog_layout_time_desc'});
# текст название программы
$widgets->{'prog_layout_name'} = Gtk2::Pango::Layout->new ( $widgets->{'prog_context_time'} );
$widgets->{'prog_layout_name'}->set_font_description ( Gtk2::Pango::FontDescription->from_string (PROG_FONT) );
$widgets->{'prog_layout_name_color_t1'} = Gtk2::Gdk::Color->new (0xFFFF, 0xFFFF, 0xFFFF); # по умолчанию
$widgets->{'prog_layout_name_color_t2'} = Gtk2::Gdk::Color->new (0xf444, 0xa666, 0xa666); # новости
$widgets->{'prog_layout_name_color_t3'} = Gtk2::Gdk::Color->new (0xf444, 0xf666, 0x8aaa); # фильм



# нарисовать список каналов
$widgets->{'channel_drawArea'} = Gtk2::DrawingArea->new;
$widgets->{'channel_drawArea'}->set_size_request( CHL_WIDTH, ($CONF{'back_height'} - PROG_FRAME_Y) );
$widgets->{'frame_chls'} = new Gtk2::Fixed();
$widgets->{'frame_chls'}->set_size_request( CHL_WIDTH, ($CONF{'back_height'} - PROG_FRAME_Y) );
$widgets->{'frame_chls'}->put( $widgets->{'channel_drawArea'}, 0, 0 );

# канальные виджеты
$widgets->{'chl_text_matrix'} = Gtk2::Pango::Matrix->new;
$widgets->{'chl_text_width'} = $widgets->{'channel_drawArea'}->allocation->width;
$widgets->{'chl_text_height'} = $widgets->{'channel_drawArea'}->allocation->height;

$widgets->{'chl_text_context'} = $widgets->{'channel_drawArea'}->create_pango_context;
$widgets->{'chl_text_context_layout'} = Gtk2::Pango::Layout->new ( $widgets->{'chl_text_context'} );

$widgets->{'chl_text_context_layout_desc'} = Gtk2::Pango::FontDescription->from_string ("verdana normal 22px");
$widgets->{'chl_text_context_layout'}->set_font_description ( $widgets->{'chl_text_context_layout_desc'} );

# цвет фона (для всей сетки)
$widgets->{'bg_white'} = Gtk2::Gdk::Color->new (0x2999, 0x5222, 0x8444);
$widgets->{'bg_black'} = Gtk2::Gdk::Color->new (0x1888, 0x3999, 0x6333);


# выводить время
$widgets->{'timeLine_dw'} = Gtk2::DrawingArea->new;
$widgets->{'timeLine_dw'}->set_size_request( $CONF{'back_width'}, TIMELINE_HEIGHT );
#$widgets->{'timeLine_imgs_1'} = Gtk2::Gdk::Pixbuf->new_from_file ($filePath.'/'."timeStatic.png");
$widgets->{'timeLine_imgs_2'} = Gtk2::Gdk::Pixbuf->new_from_file ($filePath.'/'."timeLine.png");
$widgets->{'timeLine_matrix'} = Gtk2::Pango::Matrix->new;
$widgets->{'timeLine_context'} = $widgets->{'timeLine_dw'}->create_pango_context;
$widgets->{'timeLine'} = Gtk2::Pango::Layout->new ( $widgets->{'timeLine_context'} );
$widgets->{'timeLine'}->set_font_description ( Gtk2::Pango::FontDescription->from_string ("verdana normal 28px") );
#$widgets->{'timeStatic'} = Gtk2::Pango::Layout->new ( $widgets->{'timeLine_context'} );
#$widgets->{'timeStatic'}->set_font_description ( Gtk2::Pango::FontDescription->from_string ("arial normal 23px") );


# выводить дату
$widgets->{'date_dw'} = Gtk2::DrawingArea->new;
$widgets->{'date_dw'}->set_size_request(BANNER_WIDTH, DATE_WIDTH );
$widgets->{'date_matrix'} = Gtk2::Pango::Matrix->new;
$widgets->{'date_bg'} = Gtk2::Gdk::Pixbuf->new_from_file ($filePath.'/'."dateTimeBg.png");
$widgets->{'date_context'} = $widgets->{'date_dw'}->create_pango_context;
$widgets->{'date_text'} = Gtk2::Pango::Layout->new ( $widgets->{'date_context'} );
$widgets->{'date_text'}->set_font_description ( Gtk2::Pango::FontDescription->from_string ("verdana normal 19px") );
$widgets->{'time_text'} = Gtk2::Pango::Layout->new ( $widgets->{'date_context'} );
$widgets->{'time_text'}->set_font_description ( Gtk2::Pango::FontDescription->from_string ("verdana normal 28px") );




# создать главный лого
$widgets->{'logo'} = new Gtk2::Fixed();
$widgets->{'logo'}->set_size_request(BANNER_WIDTH, BANNER_HEIGHT);
$widgets->{'logo'}->put( new_from_file Gtk2::Image( $filePath.'/'."logo.png" ), 0, 0 );


## верхний баннер
$widgets->{'banner_1_socket'} = new Gtk2::Socket;
$widgets->{'banner_1_socket_box'} = new Gtk2::EventBox;
$widgets->{'banner_1_socket_box'}->set_size_request(BANNER_WIDTH, BANNER_HEIGHT);
$widgets->{'banner_1_socket_box'}->add( $widgets->{'banner_1_socket'} );


## верхний баннер
$widgets->{'banner_2_socket'} = new Gtk2::Socket;
$widgets->{'banner_2_socket_box'} = new Gtk2::EventBox;
$widgets->{'banner_2_socket_box'}->set_size_request(BANNER_WIDTH, BANNER_HEIGHT);
$widgets->{'banner_2_socket_box'}->add( $widgets->{'banner_2_socket'} );





# создать картинку фон
$widgets->{'fon'} = new Gtk2::Fixed();
$widgets->{'fon'}->set_size_request($CONF{'back_width'}, PROG_FRAME_Y);
$widgets->{'fon'}->put( new_from_file Gtk2::Image( $filePath.'/'."fon.png" ), 0, 0 );


# $widgets->{'prog_drawArea'}->signal_connect( expose_event => \&draw_programms_nets );
# $widgets->{'channel_drawArea'}->signal_connect( expose_event => \&draw_channels );

$widgets->{'frame_nets'} = new Gtk2::Fixed();



$widgets->{'frame_nets'}->put( $widgets->{'fon'}, 0, 0 );
$widgets->{'frame_nets'}->put( $widgets->{'timeLine_dw'}, 0, (PROG_FRAME_Y - TIMELINE_HEIGHT) );
$widgets->{'frame_nets'}->put( $widgets->{'date_dw'}, CONT_LEFT_OFFSET, (CONT_TOP_OFFSET+BANNER_HEIGHT*3) );
$widgets->{'frame_nets'}->put( $widgets->{'logo'}, CONT_LEFT_OFFSET, CONT_TOP_OFFSET );
$widgets->{'frame_nets'}->put( $widgets->{'banner_1_socket_box'}, CONT_LEFT_OFFSET, (CONT_TOP_OFFSET+BANNER_HEIGHT) );
$widgets->{'frame_nets'}->put( $widgets->{'banner_2_socket_box'}, CONT_LEFT_OFFSET, (CONT_TOP_OFFSET+BANNER_HEIGHT*2) );


$widgets->{'frame_nets'}->put( $widgets->{'frame_prog'}, CHL_WIDTH, PROG_FRAME_Y );
$widgets->{'frame_nets'}->put( $widgets->{'frame_chls'}, 0, PROG_FRAME_Y );




# вставить сетку программ в главную таблицу
$widgets->{'main_table'}->attach($widgets->{'frame_nets'}, 0, 1, 0, 1, [ 'expand', 'fill' ], ['expand', 'fill'], 0, 0 );



$window->add( $widgets->{'main_table'} );


$widgets->{'prog_drawArea'}->signal_connect( expose_event => \&draw_programms_nets );
$widgets->{'channel_drawArea'}->signal_connect( expose_event => \&draw_channels );
$widgets->{'timeLine_dw'}->signal_connect( expose_event => \&time_line );
$widgets->{'date_dw'}->signal_connect( expose_event => \&draw_date );


# записать данные о в sys_swap

{
# открыть коннект с базой
	my $DBH = Open_DB ($CONF{'DBNAME'}, $CONF{'DBHOST'}, $CONF{'DBUSER'}, $CONF{'DBPASS'});
	$sql = sprintf (
		"replace into sys_swap (param, arg, time) values ('%s', '%s', %d )",
		'gscreen_load_pid',
		$pid,
		time()
	);
	$sth = $DBH->prepare($sql);
	$sth->execute();
	$sth->finish();

	$sql = sprintf (
		"replace into sys_swap (param, arg, time) values ('%s', '%s', %d )",
		'video_width', VIDEO_WIDTH, time()
		);
	$sth = $DBH->prepare($sql);
	$sth->execute();
	$sth->finish();

	$sql = sprintf (
		"replace into sys_swap (param, arg, time) values ('%s', '%s', %d )",
		'video_height', VIDEO_HEIGHT, time()
		);
	$sth = $DBH->prepare($sql);
	$sth->execute();
	$sth->finish();

	$sql = sprintf (
		"replace into sys_swap (param, arg, time) values ('%s', '%s', %d )",
		'video_wid',
		$widgets->{'frame_socket'}->get_id,
		time()
	);
	$sth = $DBH->prepare($sql);
	$sth->execute();
	$sth->finish();

	$sql = sprintf (
		"replace into sys_swap (param, arg, time) values ('%s', '%s', %d )",
		'banner1_wid',
		$widgets->{'banner_1_socket'}->get_id,
		time()
	);
	$sth = $DBH->prepare($sql);
	$sth->execute();
	$sth->finish();

	$sql = sprintf (
		"replace into sys_swap (param, arg, time) values ('%s', '%s', %d )",
		'banner2_wid',
		$widgets->{'banner_2_socket'}->get_id,
		time()
	);
	$sth = $DBH->prepare($sql);
	$sth->execute();
	$sth->finish();

	$sql = sprintf (
		"replace into sys_swap (param, arg, time) values ('%s', '%s', %d )",
		'gscreen_pid',
		$pid,
		time()
	);
	$sth = $DBH->prepare($sql);
	$sth->execute();
	$sth->finish();

	Close_DB ($DBH)
}



my $timeout_id = Glib::Timeout->add (80, \&timeout);


if (!$window->visible) {
	$window->show_all;
} else {
	$window->destroy;
	$window = undef;
}

Gtk2->main;

undef $window;




sub nets_reload {
	
	$CHANNELS = {};
	$CHANNELS_DATA = {};
	$PROGRAMMS = {};
	$TOTAL_CHANNELS = 0;
	my ($mday, $month, $year) = (localtime(time()))[3,4,5];
	my ($old_mday, $old_month, $old_year) = (localtime(time()-86400))[3,4,5];	
	my %netDayStart = ();
	$MOVE->{'y-place'} = 0;

	my $DBH = Open_DB ($CONF{'DBNAME'}, $CONF{'DBHOST'}, $CONF{'DBUSER'}, $CONF{'DBPASS'});

	# грузим начало дня каналов
	$sql = sprintf("select resource_id, start_day_hour, start_day_minute from media_resources");
	$sth = $DBH->prepare($sql);
	$sth->execute();
	while ( my($resource_id, $start_day_hour, $start_day_minute) = $sth->fetchrow_array() ) {
		$netDayStart{$resource_id} = time2sec( $start_day_hour.':'.$start_day_minute.':00' );
	}
	$sth->finish();	

	# грузим старую сетку
	$sql = sprintf('select
nets_progs.prog_id,
nets_progs.resource_id,
nets_progs.sTimeId,
nets_progs.dTimeId,
nets_progs.cols,
nets_progs.name
from nets
join media_resources
join nets_progs on nets.net_id=nets_progs.net_id and nets_progs.sTimeId>=86400 and nets_progs.resource_id=media_resources.resource_id 
where nets.switch=1
and nets.mday=%d
and nets.month=%d
and nets.year=%d
order by media_resources.resource_num asc, nets_progs.sTimeId asc', $old_mday, ($old_month+1), ($old_year+1900)) ;
	$sth = $DBH->prepare($sql);
	$sth->execute();
	while ( my($prog_id, $resource_id, $sTimeId, $dTimeId, $cols, $name) = $sth->fetchrow_array() ) {
		$sTimeId -= 86400; $dTimeId -= 86400;
		next if $dTimeId > $netDayStart{$resource_id};
		$name =~ s/\s+$//;
		$name =~ s/^\s+//;
		$name =~ s,\s+, ,g;
		push_programm($prog_id, $resource_id, $sTimeId, $cols, decode_utf8(koi2utf($name)), sec2time($sTimeId) );
	}
	$sth->finish();


	# грузим сетку
	$sql = sprintf('select
nets_progs.prog_id,
nets_progs.resource_id,
nets_progs.sTimeId,
nets_progs.dTimeId,
nets_progs.cols,
nets_progs.name
from nets
join media_resources
join nets_progs on nets.net_id=nets_progs.net_id and nets_progs.resource_id=media_resources.resource_id
where nets.switch=1
and nets.mday=%d
and nets.month=%d
and nets.year=%d
order by media_resources.resource_num asc, nets_progs.sTimeId asc', $mday, ($month+1), ($year+1900));
	$sth = $DBH->prepare($sql);
	$sth->execute();
	while ( my($prog_id, $resource_id, $sTimeId, $dTimeId, $cols, $name) = $sth->fetchrow_array() ) {
		$name =~ s/\s+$//;
		$name =~ s/^\s+//;
		$name =~ s,\s+, ,g;
		push_programm($prog_id, $resource_id, $sTimeId, $cols, decode_utf8(koi2utf($name)), sec2time($sTimeId) );
	}
	$sth->finish();

	$sql = sprintf("select
media_resources.resource_id,
media_resources.r_name,
media_resources.logo_id,
media_resources_logos.suf,
media_resources.resource_num,
media_resources.start_day_hour,
media_resources.start_day_minute
from
media_resources
left join media_resources_logos on media_resources_logos.logo_id=media_resources.logo_id
order by media_resources.resource_num asc");
	$sth = $DBH->prepare($sql);
	$sth->execute();
	while ( my($resource_id, $r_name, $logo_id, $logo_suf, $resource_num, $start_day_hour, $start_day_minute) = $sth->fetchrow_array() ) {
		$netDayStart{$resource_id} = time2sec( $start_day_hour.':'.$start_day_minute.':0' );
		graw_channel($resource_id, $resource_num, decode_utf8(koi2utf($r_name)), $logo_id, $logo_suf);
	}
	$sth->finish();	
	Close_DB ($DBH);
	$lastDBconnect = time();
}



sub draw_programms_nets {
#	my ($widget, $event) = @_;

	my $text_matrix = Gtk2::Pango::Matrix->new;

	my $text_renderer = Gtk2::Gdk::PangoRenderer->get_default ($widgets->{'prog_drawArea'}->get_screen);
	$text_renderer->set_drawable ($widgets->{'prog_drawArea'}->window);
	$text_renderer->set_gc ($widgets->{'prog_drawArea'}->style->black_gc);

#	$widgets->{'prog_drawArea'}->set_size_request( ($CONF{'back_width'} - CHL_WIDTH), PROG_FRAME_offsetY );


	# программа
	my $gc = Gtk2::Gdk::GC->new ($widgets->{'prog_drawArea'}->window);
	# бордеры
	my $gc2 = Gtk2::Gdk::GC->new ($widgets->{'prog_drawArea'}->window);
	$gc2->set_rgb_fg_color (Gtk2::Gdk::Color->parse ('black'));


	foreach my $rid ( sort { $CHANNELS->{$a}->{'num'} <=> $CHANNELS->{$b}->{'num'} } keys %$CHANNELS ) {
		my $screenY = $CHANNELS->{$rid}->{'workY'};
		$screenY -= $MOVE->{'y-place'};
		next if (  $screenY > ($CONF{'back_height'} - PROG_FRAME_Y) || 0 > ( $screenY + PROG_HEIGHT ) );

		# цвет фона
		$gc->set_rgb_fg_color ( ( $CHANNELS->{$rid}->{'num'} % 2 ? $widgets->{'bg_white'} : $widgets->{'bg_black'} ) );
		$widgets->{'prog_drawArea'}->window->draw_rectangle ( $gc, TRUE, 0, $screenY, ($CONF{'back_width'} - CHL_WIDTH), PROG_HEIGHT );

		for (my $n = 0; $n < @{$CHANNELS->{$rid}->{'progs'}}; $n++ ) {
			my $prog_id = $CHANNELS->{$rid}->{'progs'}->[$n];
			my $prog = $PROGRAMMS->{$prog_id};
			my $screenX = $PROGRAMMS->{$prog_id}->{'screenX'};
			$screenX -= $MOVE->{'x-place'};

			# приделы прорисовки по X
			next if (  $screenX > ($CONF{'back_width'} - CHL_WIDTH) || 0 > ( $screenX + $prog->{'offsetX'} )  );

#			# фон
#			$widgets->{'prog_drawArea'}->window->draw_rectangle ( $gc, TRUE, $screenX, $screenY, $prog->{'offsetX'}, $prog->{'offsetY'} );

			# левый бордер
			my $last_prog = $CHANNELS->{$rid}->{'progs'}->[($n-1)];
			if ( $last_prog && ($PROGRAMMS->{$last_prog}->{'screenX'}+$PROGRAMMS->{$last_prog}->{'offsetX'}) < $prog->{'screenX'} ) {

				$widgets->{'prog_drawArea'}->window->draw_rectangle ( $gc2, TRUE, $screenX, $screenY, PROG_BORDER, PROG_HEIGHT );
			}
			# правый бордер
			$widgets->{'prog_drawArea'}->window->draw_rectangle ( $gc2, TRUE, ($prog->{'offsetX'} - PROG_BORDER + $screenX ), $screenY, PROG_BORDER, PROG_HEIGHT );


#			{ # время
#				$widgets->{'prog_layout_time'}->set_text ( $prog->{'form_time'} );
#				my $text_rotated_matrix = $text_matrix->copy;
#				$text_rotated_matrix->translate ( $screenX + 6, $screenY + 4);
#				$text_renderer->set_override_color ('foreground', $prog->{'numChls'} % 2 ? $widgets->{'prog_layout_time_color1'} : $widgets->{'prog_layout_time_color2'} );
#				$widgets->{'prog_context_time'}->set_matrix ($text_rotated_matrix);
#				$text_renderer->draw_layout ($widgets->{'prog_layout_time'}, 1, 1);
#			}

			{ # название
				my $name = $prog->{'name'};
				my $slide = 0;
				my $maxWidth = $prog->{'offsetX'} - PROG_BORDER - 3;
				my $progStart = $screenX + $slide + 3;
				$widgets->{'prog_layout_time'}->set_text ( $name );
				my ($textwidth, $textheight) = $widgets->{'prog_layout_time'}->get_pixel_size;

				my $text_rotated_matrix = $text_matrix->copy;
			
				if ( $textwidth > $maxWidth ) {
					my @word = split('\s', $name);
					$name = '';
					my $n=0;
					my $elem = 0;
					while ($n<2 && $elem < scalar(@word) ) {
						$word[$n] = '' unless $word[$n];
						my $w = $word[$elem];
						my $nx = $n+1;
						$w .= ' '.$word[++$elem] if length($w) < 4 && $word[$nx];
						$w = substr($w, 0, int(($prog->{'offsetX'} - 2 - PROG_BORDER)/FONT_WIDTH) );
						$name .= $w."\n";
						$elem++; $n++;
					}
					$widgets->{'prog_layout_time'}->set_markup("<span size='16500'>".$name."</span>");
					$text_rotated_matrix->translate ( $progStart, ($screenY + ( $n == 1 ? 9 : 3)) );
				} else {
					$widgets->{'prog_layout_time'}->set_markup(
							"<span size='13000'>".'['.$prog->{'form_time'}.']'."</span> <span size='17000'>".$name."</span>");
#					$widgets->{'prog_layout_time'}->set_text ('['.$prog->{'form_time'}.'] '.$name);
					my ($textwidth, $textheight) = $widgets->{'prog_layout_time'}->get_pixel_size;
					$widgets->{'prog_layout_time'}->set_markup("<span size='16500'>".$name."</span>") if $maxWidth <= $textwidth;
					
					if ( $progStart < 0 ) {
						my $offset = $progStart*-1 + $textwidth + 3;
						$progStart = 3 if $offset < $maxWidth;
						$progStart = $maxWidth - $offset if $offset > $maxWidth;
					}
					$text_rotated_matrix->translate ( $progStart, $screenY + 9);
				}

				$text_renderer->set_override_color ('foreground', $widgets->{'prog_layout_name_color_t'.$prog->{'type'} } );
				$widgets->{'prog_context_time'}->set_matrix ($text_rotated_matrix);
				$widgets->{'prog_layout_time'}->context_changed;
				$text_renderer->draw_layout ($widgets->{'prog_layout_time'}, 1, 1);
			}

		}

		# верхний бордер
		$widgets->{'prog_drawArea'}->window->draw_rectangle ( $gc2, TRUE, 0, $screenY, ($CONF{'back_width'} - CHL_WIDTH), PROG_BORDER );
		# нижний бордер
#		$widgets->{'prog_drawArea'}->window->draw_rectangle ( $gc2, TRUE, 0, (PROG_HEIGHT - PROG_BORDER + $screenY), ($CONF{'back_width'} - CHL_WIDTH), PROG_BORDER );
	}

	$text_renderer->set_override_color ('foreground', undef);
	$text_renderer->set_drawable (undef);
	$text_renderer->set_gc (undef);

  return FALSE;
}


sub draw_channels {
#	my ($widget, $event) = @_;

	my $text_renderer = Gtk2::Gdk::PangoRenderer->get_default ($widgets->{'channel_drawArea'}->get_screen);
	$text_renderer->set_drawable ($widgets->{'channel_drawArea'}->window);
	$text_renderer->set_gc ($widgets->{'channel_drawArea'}->style->black_gc);

	foreach my $rid ( sort { $CHANNELS->{$a}->{'num'} <=> $CHANNELS->{$b}->{'num'} } keys %$CHANNELS ) {

		my $chl = $CHANNELS->{$rid}->{'data'};
		my $Y = $CHANNELS->{$rid}->{'workY'};
		my $Y_last = PROG_HEIGHT;

		$CHANNELS->{$rid}->{'workY'} += ($TOTAL_CHANNELS * PROG_HEIGHT) if ( ( ($CHANNELS->{$rid}->{'workY'} + PROG_HEIGHT) - $MOVE->{'y-place'}) < 0);

		$Y -= $MOVE->{'y-place'};
		next if (  $Y > ($CONF{'back_height'} - PROG_FRAME_Y) || 0 > ( $Y + $Y_last ) );


		$widgets->{'chl_gc'} = Gtk2::Gdk::GC->new ( $widgets->{'channel_drawArea'}->window );
		# цвет фона
		$widgets->{'chl_gc'}->set_rgb_fg_color ( ( $CHANNELS->{$rid}->{'num'} % 2 ? $widgets->{'bg_white'} : $widgets->{'bg_black'} ) );

		# фон
		$widgets->{'channel_drawArea'}->window->draw_rectangle ( $widgets->{'chl_gc'}, TRUE, 0, $Y, CHL_WIDTH, PROG_HEIGHT );

		# бордеры
		$widgets->{'chl_gc'}->set_rgb_fg_color (Gtk2::Gdk::Color->parse ('black'));
		# нижний
		$widgets->{'channel_drawArea'}->window->draw_rectangle(
						$widgets->{'chl_gc'},
						TRUE,
						0,
						$Y,
						CHL_WIDTH,
						PROG_BORDER
					);

		my $color = Gtk2::Gdk::Color->new (0x1333, 0x2eee, 0x5000);
		$widgets->{'chl_gc'}->set_rgb_fg_color ($color);
		$widgets->{'channel_drawArea'}->window->draw_rectangle(
						$widgets->{'chl_gc'},
						TRUE,
						(CHL_WIDTH - PROG_BORDER ),
						($Y+PROG_BORDER),
						PROG_BORDER,
						PROG_HEIGHT
					);

		my $name = $chl->{'name'};
		my $xoff = 20;

#	background = '#000000' 
#	foreground= '#00FF00' 
#weight = 'ultralight'
		$widgets->{'chl_text_context_layout'}->set_markup(
"<span size='15000'>".$chl->{'num'}."</span>\n<span size='16500'>".uc($name)."</span>");

#		$widgets->{'chl_text_context_layout'}->set_text ( $chl->{'num'}."\n".uc($name) );
		
		$widgets->{'chl_text_context_layout'}->set_alignment('center');
		my ($textwidth, $textheight) = $widgets->{'chl_text_context_layout'}->get_pixel_size;
		$xoff += int((CHL_WIDTH - $xoff - 38)/2 - $textwidth/2);

#		$widgets->{'chl_text_context_layout'}->set_pixel_size(70);

		my $text_rotated_matrix = $widgets->{'chl_text_matrix'}->copy;
		$text_rotated_matrix->translate ( $xoff, $Y + 2);
		
		my $text_color = Gtk2::Gdk::Color->new (0xffff, 0xffff, 0xffff);
		$text_renderer->set_override_color ('foreground', $text_color);
		$widgets->{'chl_text_context'}->set_matrix ($text_rotated_matrix);
		$widgets->{'chl_text_context_layout'}->context_changed;
		$text_renderer->draw_layout ($widgets->{'chl_text_context_layout'}, 1, 1);

		# логотип канала
		if ( $chl->{'logo'} ) {
			my ($logoX, $logoY) = ( (CHL_WIDTH - LOGO_SIZE - LOGO_RIGHT_offset), (LOGO_TOP_offset + $Y) );
			$chl->{'logo'}->render_to_drawable (
					$widgets->{'channel_drawArea'}->window,
					$widgets->{'channel_drawArea'}->style->black_gc,
					0, 0,
					$logoX, $logoY,
					LOGO_SIZE, LOGO_SIZE,
					'normal',
					$logoX, $logoY
				);
		}

	}
	$text_renderer->set_override_color ('foreground', undef);
	$text_renderer->set_drawable (undef);
	$text_renderer->set_gc (undef);
	return FALSE;
}




sub push_programm {
	my ($prog_id, $rid, $sTimeId, $length, $name, $form_time) = @_;

	return undef if ( exists $PROGRAMMS->{$prog_id} );

	$length *= PROG_TIME_STEP; #временная длина * на шаг сетки
	my $numChls = 0;

	my @arr = ();
	$CHANNELS->{$rid}->{'progs'} = \@arr unless ref $CHANNELS->{$rid};

	my ($last_screenX, $last_elem) = ( 0, scalar( @{$CHANNELS->{$rid}->{'progs'}} ) );

	unless ( $last_elem ) {
		$last_screenX = 0;
		$numChls = scalar keys %{$CHANNELS};
		$numChls--;
	}

	if ( $last_elem-- ) {
		$last_screenX =
					$PROGRAMMS->{ $CHANNELS->{$rid}->{'progs'}->[$last_elem] }->{'screenX'}
						+ $PROGRAMMS->{ $CHANNELS->{$rid}->{'progs'}->[$last_elem] }->{'offsetX'};

		$numChls = $PROGRAMMS->{ $CHANNELS->{$rid}->{'progs'}->[$last_elem] }->{'numChls'};
	}

	$PROGRAMMS->{$prog_id} = {
		'numChls' => $numChls,
		'screenX' => ( ($sTimeId/NET_STEP) * PROG_TIME_STEP),
		'screenY' => PROG_HEIGHT*$numChls,
		'offsetX' => $length,
		'offsetY' => PROG_HEIGHT,
		'rid' => $rid,
		'name' => $name,
		'color' => "#FFFFFF",
		'form_time' => $form_time,
		'type' => 1
	};

	$PROGRAMMS->{$prog_id}->{'type'} = 2 if ( $name=~ m/новости/i );
	$PROGRAMMS->{$prog_id}->{'type'} = 3 if ( $name=~ m,х/?ф,i );

	$CHANNELS->{$rid}->{'num'} = $numChls;
	$CHANNELS->{$rid}->{'workY'} = $numChls * PROG_HEIGHT;
	push ( @{$CHANNELS->{$rid}->{'progs'} }, $prog_id);

}


sub graw_channel {
	my ($rid, $num, $name, $logo, $logo_suf) = @_;
	return unless ref $CHANNELS->{$rid};
	$logo_suf = 'gif' unless $logo_suf;
	my $LogoFile = $CONF{'HTDOCSDIR'}.$CONF{'CHLLOGODIR'}.'/'.$logo.'.'.$logo_suf;
#	my $Image = undef ();
#	my $Image_new = new GD::Image(LOGO_SIZE, LOGO_SIZE);
#	$Image = GD::Image->newFromJpeg ($LogoFile) if ($logo_suf eq 'jpg');
#	$Image = GD::Image->newFromGif ($LogoFile) if ($logo_suf eq 'gif');
#	$Image = GD::Image->newFromPng ($LogoFile, 1) if ($logo_suf eq 'png');
#	$Image_new->copyResized($Image, 0, 0, 0, 0, LOGO_SIZE, LOGO_SIZE, $Image->width, $Image->height);
	
	$CHANNELS->{$rid}->{'data'}->{'name'} = $name;
	$CHANNELS->{$rid}->{'data'}->{'num'} = $num;
	$CHANNELS->{$rid}->{'data'}->{'logo'} = Gtk2::Gdk::Pixbuf->new_from_file_at_scale ($LogoFile, LOGO_SIZE, LOGO_SIZE, 0);

#	if ( $logo != 0 ) {
	$CHANNELS->{$rid}->{'data'}->{'logo_width'} = $CHANNELS->{$rid}->{'data'}->{'logo'}->get_width;
	$CHANNELS->{$rid}->{'data'}->{'logo_height'} = $CHANNELS->{$rid}->{'data'}->{'logo'}->get_height;
#$CHANNELS->{$rid}->{'data'}->{'logo_width'} = LOGO_SIZE;
#$CHANNELS->{$rid}->{'data'}->{'logo_height'} = LOGO_SIZE;
#	}

	$TOTAL_CHANNELS = scalar keys %{$CHANNELS};
}



sub time_line {
	my ($widget, $event) = @_;

	# временная шкала
	$widgets->{'timeLine_imgs_2'}->render_to_drawable (
				$widget->window,
				$widget->style->black_gc,
				0, 0,
				0, 0,
				$CONF{'back_width'}, TIMELINE_HEIGHT,
				'normal',
				0, 0
		);
	my $text_renderer = Gtk2::Gdk::PangoRenderer->get_default ($widget->get_screen);

	$text_renderer->set_drawable ($widget->window);
	$text_renderer->set_gc ($widget->style->black_gc);

	my $count_start = int( ($MOVE->{'x-place'} + CHL_WIDTH) / (PROG_TIME_STEP * 6 ) );
	my $count_last = int( ($CONF{'back_width'} - CHL_WIDTH + $MOVE->{'x-place'}) / (PROG_TIME_STEP * 6 ) );

	for ( my $n = ($count_start); $n <= $count_last; $n++) {
		my $X = ($n * PROG_TIME_STEP * 6 + CHL_WIDTH ) - $MOVE->{'x-place'};
			next if $X < 0;

			my $gc = Gtk2::Gdk::GC->new ( $widget->window );
			$gc->set_rgb_fg_color ( Gtk2::Gdk::Color->new (0xffff, 0xffff, 0xffff) );
			$widget->window->draw_rectangle ( $gc, TRUE, ($X-3), 5, 3, 28 );
		
			$widgets->{'timeLine'}->set_text ( sec2time($n*1800) );
			my $text_rotated_matrix = $widgets->{'timeLine_matrix'}->copy;
			$text_rotated_matrix->translate ( ($X+9), 2);
			my $text_color = Gtk2::Gdk::Color->new (0xffff, 0xffff, 0xffff);
			$text_renderer->set_override_color ('foreground', $text_color);
			$widgets->{'timeLine_context'}->set_matrix ($text_rotated_matrix);

			$widgets->{'timeLine'}->context_changed;
			$text_renderer->draw_layout ($widgets->{'timeLine'}, 1, 1);

	}
	$text_renderer->set_override_color ('foreground', undef);
	$text_renderer->set_drawable (undef);
	$text_renderer->set_gc (undef);
}


sub draw_date {
	my ($widget, $event) = @_;
	
	# фод для даты
	$widgets->{'date_bg'}->render_to_drawable (
		$widget->window,
		$widget->style->black_gc,
		0, 0,
		0, 0,
		BANNER_WIDTH, DATE_WIDTH,
		'normal',
		0, 0
		);

	my $text_renderer = Gtk2::Gdk::PangoRenderer->get_default ( $widgets->{'date_dw'}->get_screen );
	$text_renderer->set_drawable ( $widgets->{'date_dw'}->window );
	$text_renderer->set_gc ( $widgets->{'date_dw'}->style->black_gc );
	my $gc = Gtk2::Gdk::GC->new ( $widgets->{'date_dw'}->window );
	# цвет фона

	my ( $mday, $mon, $wday ) = (localtime)[3,4,6];
	$wday = 7 if ( $wday == 0 ); $wday--;
	
	$widgets->{'time_text'}->set_text (
		sprintf("%02d:%02d", (localtime)[2], (localtime)[1])
	 );
	
	$widgets->{'date_text'}->set_text (
		$mday ." " . 
		uc($MoY[$mon]) . ", " . 
		uc($DoW[$wday])
	 );

	
	my $text_rotated_matrix = $widgets->{'date_matrix'}->copy;
	$text_rotated_matrix->translate ( 93, 12);
	$text_renderer->set_override_color ('foreground', Gtk2::Gdk::Color->new (0xffff, 0xffff, 0xffff) );
	$widgets->{'date_context'}->set_matrix ($text_rotated_matrix);
	$widgets->{'date_text'}->context_changed;
	$text_renderer->draw_layout ( $widgets->{'date_text'}, 1, 1 );

	$text_rotated_matrix = $widgets->{'date_matrix'}->copy;
	$text_rotated_matrix->translate ( 4, 7);
	$text_renderer->set_override_color ('foreground', Gtk2::Gdk::Color->new (0xffff, 0xffff, 0xffff) );
	$widgets->{'date_context'}->set_matrix ($text_rotated_matrix);
	$widgets->{'time_text'}->context_changed;
	$text_renderer->draw_layout ( $widgets->{'time_text'}, 1, 1 );

	$text_renderer->set_override_color ('foreground', undef);
	$text_renderer->set_drawable (undef);
	$text_renderer->set_gc (undef);
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
	if ( exists $PARAM{'nets_reload'} ) {
		$sth = $DBH->prepare("delete from sys_swap where param='nets_reload'");
		$sth->execute();
		$sth->finish();
		nets_reload ();
	}	
	Close_DB ($DBH);
	$lastDBconnect = time();
}


sub timeout {
	my $unix_time = time();
	my $time = time2sec(sprintf("%d:%d:%d", (localtime($unix_time))[2,1,0]));
	$time = int ( $time/(NET_STEP / PROG_TIME_STEP) );
	reload_param() if ( ($unix_time - $lastDBconnect) > DB_RECHECK );
	$MOVE->{'x-place'} = $time;
	$MOVE->{'y-place'} += 1;
	$widgets->{'prog_drawArea'}->queue_draw;
	$widgets->{'channel_drawArea'}->queue_draw;
	$widgets->{'timeLine_dw'}->queue_draw;
	$widgets->{'date_dw'}->queue_draw;
	return TRUE;
}


sub koi2utf {
	my $s = shift;
	my $converter = Text::Iconv->new("koi8r", "utf8");
	$s = $converter->convert($s);
	return $s;
}

sub utf2koi {
	my $s = shift;
	my $converter = Text::Iconv->new("utf8", "koi8r");
	$s = $converter->convert($s);
	return $s;
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

sub sec2time {
	my $sec = shift;
	if (!$sec) { $sec = 0; };
	$sec = ( $sec - 86400 ) if ($sec > 86400);
	my $hour = int($sec/3600);
	my $min = int( ($sec-$hour*3600) / 60 );
	$sec = $sec - ($hour*3600+$min*60);
	if ($hour < 10) { $hour = "0".$hour; }
	if ($min < 10) { $min = "0".$min; }
	return $hour.':'.$min;
}

sub time2sec {
	my @t = split(':', shift);
	my $sec = 0;
	$sec = $t[0]*3600 + $t[1]*60 + $t[2]*1 if ( scalar(@t) == 3 );
	$sec = $t[0]*60 + $t[1]*1 if ( scalar(@t) == 2 );
	$sec = $t[0]*1 if ( scalar(@t) == 1 );
	return $sec;
}

# function sec2time (sec) {
# 	if ( !isFinite(sec) ) sec = 0;
# 	sec = Number(sec).toFixed(0);
# 	if (sec>86400) sec = sec - 86400;
# 	var hour = Math.floor(sec/3600);
# 	var min = Math.floor( (sec-hour*3600) / 60 );
# 	sec = sec - (hour*3600+min*60);
# 	if (hour < 10) hour = "0"+hour;
# 	if (min < 10) min = "0"+min;
# 	if (sec < 10) sec = "0"+sec;
# 	return ( Number(hour) != 0 ? hour+":" : '') + min + ":" +sec;
# }


#		my $cmd = sprintf(
#			'|%s -slave -wid %d -geometry %dx%d %s "%s" 1>/dev/null 2>/dev/null',
#			$self->get('mplayer_path'),
#			$self->get_id,
#			$self->allocation->width,
#			$self->allocation->height,
#			$self->get('args'),
#			$file
#		);



sub logger {
	my $s = shift;
	print localtime()." ".$s."\n";
}