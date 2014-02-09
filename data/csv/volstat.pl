#!/usr/bin/perl 
# Лицензия "Делайте что хотите", а если очень нужно, то GPL :) 
# Сообщения на английском, чтобы не связываться с локалями и gettext :( .

# Назначение
# Посчитать статистику слов и УВ

use POSIX;
use utf8;
use Encode;

# Настройки
our $n = "\n"; # символ новой строки для вывода файлов

# Статистика
#our $statinelex = 0; # Всего англ. статей

our %stat; # Хранилище данных общего словаря

sub readunlvol ($) { # Чтение UNL-словаря-посредника
    my ($file) = @_;
    my ($uw, $etapuw, $dummy, $comm, $ex, $status, $author, $freq, $wn21, $wn30, $sumo, $srclang);
    my (%uwree, %uwtree2); # Для разбора и сравнения 2 УВ

    open (SRC, "< $file");

    while (<SRC>) {
	s/$n$//;
	s/;$//;
	chomp;
	$_ = decode("utf-8", $_);
	if ($file =~ m/^unlvolume/) {
	    ($uw, $etapuw, $history, $comm, $ex, $dummy, $status, $author, $freq, $wn21, $wn30, $sumo, $srclang) = split(/	/, $_);
	} else {
	    ($w, $proc, $uw, $comm, $ex, $pos, $status, $author) = split(/	/, $_);
	};
	
	if ($w and $w =~ m/^\[(.*)\]$/) {$w = $1};
	if ($uw and $uw =~ m/^[\[\"](.*)[\]\"]$/) {$uw = $1};
	if ($etapuw and $etapuw =~ m/^\{(.*)\}$/) {$etapuw = $1};
	if ($comm and $comm =~ m/^\"(.*)\"$/) {$comm = $1};
	if ($ex and $ex =~ m/^\"(.*)\"$/) {$ex = $1};
	if ($srclang and $srclang =~ m/^\"(.*)\"$/) {$srclang = $1};
	if ($freq and $freq =~ m/^FREQ\=(\d+)$/) {$freq = $1};
	if ($proc =~ m/^\{(.*)\}$/) {$proc = $1};

	if ($uw and $uw =~ m/^[a-z0-9\.\'\_\-#&%\|]+(\([a-z0-9\.\'\_\-#&%\|\<\>\(\)\,]+\))$/i) { # Отсев мусора на месте UW

	    # Для отождествления старых и новых форм исправленных ув (аргументные ограничители)
	    #if ($wn21 =~ m/%.*\s(.*);/) { $wnindex{"$1".getuwpos($uw)}{$uw} = ''; };
	    #if ($uw =~ m/(.*?)[\(\{]/) { $hwindex{$1}{$uw} = ''; };

	    $stat{'pairs'}++;
	    if ($uw) {$stat{'uw'}{$uw} = ''};
	    if ($w) {$stat{'w'}{$w} = ''}; #print encode 'utf8', "$uw\n";
	    if ($proc) {$stat{'w_attr_count'}++};
	    $stat{'status'}{$status}++;
	    if ($sumo) {$stat{'sumo_count'}++};
	    if ($wn21) {$stat{'wn21_count'}++};
	    if ($wn30) {$stat{'wn30_count'}++};
	    if ($freq) {$stat{'freq_count'}++};
	    if ($freq > 10) {$stat{'freq10_count'}++};
	    if ($freq > 100) {$stat{'freq100_count'}++};
	    if ($author) {$stat{'author'}{$author}++};
	    if ($srclang) {$stat{'srclang'}{$srclang}++};
	
	} elsif (defined $uw) { print "Ignoring bad UW: $uw\n" };
    };

    close SRC;
}

########################### Начало
if ( not $#ARGV + 1) { 
    print "This script computes statistics of a UNL dictionary volume (in csv format).\n"
} else { 

    readunlvol ($ARGV[0]); # Прочесть имеющийся UW++ том UNL


	print encode 'utf8',  "\nTotal word-UW links:   $stat{'pairs'}\n";
	
	if (exists $stat{'uw'}) {
	    undef @_; @_ = keys %{$stat{'uw'}};
	    print encode 'utf8',  "Total number of UWs:   ".($#_ + 1)."\n";
	};
	
	if (exists $stat{'w'}) {
	    undef @_; @_ = keys %{$stat{'w'}};
	    print encode 'utf8',  "Total number of words:   ".($#_ + 1)."  ";
	    if ($stat{'w_attr_count'}) {print encode 'utf8',  "($stat{'w_attr_count'}   words have data from a processor)"};
	    print encode 'utf8',  "\n";
	};
	
	if (exists $stat{'sumo_count'}) {print encode 'utf8',  "$stat{'sumo_count'} UWs with SUMO links\n";};
	if (exists $stat{'wn21_count'}) {print encode 'utf8',  "$stat{'wn21_count'} UWs with PWN 2.1 links\n";};
	if (exists $stat{'wn30_count'}) {print encode 'utf8',  "$stat{'wn30_count'} UWs with PWN 3.0 links\n";};
	if (exists $stat{'freq_count'}) {print encode 'utf8',  "$stat{'freq_count'} UWs with Frequency measure\n";};
	if (exists $stat{'freq10_count'}) {print encode 'utf8',  "$stat{'freq10_count'} UWs with Frequency measure above 10\n";};
	if (exists $stat{'freq100_count'}) {print encode 'utf8',  "$stat{'freq100_count'} UWs with Frequency measure above 100\n";};
	    print encode 'utf8',  "\n";

	if (exists $stat{'status'}) {
	    print encode 'utf8',  "\nLink status summary:\n";
	    foreach $status (sort keys %{$stat{'status'}}) {
		print encode 'utf8',  "	$status  -  $stat{'status'}{$status}\n";
	    };
	};

	if (exists $stat{'author'}) {
	    print encode 'utf8',  "\nAuthor summary:\n";
	    foreach $author (sort keys %{$stat{'author'}}) {
		print encode 'utf8',  "	$author  -  $stat{'author'}{$author}\n";
	    };
	};

	if (exists $stat{'srclang'}) {
	    print encode 'utf8',  "\nSource language summary:\n";
	    foreach $srclang (sort keys %{$stat{'srclang'}}) {
		print encode 'utf8',  "	$srclang  -  $stat{'srclang'}{$srclang}\n";
	    };
	};

};


