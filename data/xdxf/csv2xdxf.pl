#!/usr/bin/perl -w
# This script converts the CSV form of the Universal Dictionary of Concepts into XDXF format.
# XDXF files can be viewed using dictionary shells, e.g. GoldenDict
# This converter is offered under the terms of GPLv3.

use POSIX;
use utf8;
use Encode;
use File::Spec::Functions;
use File::Basename;

# Настройки
our $n = "\n"; # символ новой строки для вывода файлов
our $outpath = catfile (getcwd(), "out");
our $sysencoding;
our $olduwdelim = '/'; # Разделитель между UW с списке устаревших форм UW
our $glosssubstrdelim = ' / '; # Разделитель между альтернативными комментариями или примерами на одном языке

our %volslist; # Собираемый список путей к файлам томов словаря
our %pivot; # Хранилище данных общего словаря
our %uwlinks; # Хранилище сем. связей между UW
our %invuwlinks; # Хранилище сем. связей между UW
our %stat; # Статистика
our %lex; # данные томов естественных языков
my $dictname = "CommonUNLDict";

our %syntags; # Хранилище данных о части речи и синт признаках (Используется при импорте новых УВ и их переводов из КС в общий словарь)
our %uwlist; # Список замен UW
our %uwfilter; # список UW для изготовления урезанных версия словаря (uwfilter{black} черный и белый uwfilter{white})

our %processors; # Список поддерживаемых процессоров для обработки отдельных языков
    $processors{'rus'} = "ETAP3";
    $processors{'eng'} = "ETAP3";
    $processors{'fra'} = "Ariane";
    $processors{'hin'} = "CFILT";
    $processors{'sumo'} = "SUMO"; # Также можно добавлять теги внешних ресурсов для вывода индекных томов 
    $processors{'sumonew'} = "SUMO-new";
    $processors{'sumoext'} = "SUMO-ext";

our %extres; # В этот список нужно добавлять теги поддерживаемых внешних ресурсов. Есть 2 формата ссылок: для ворднетов 'wn' и онтологий 'onto'
    $extres{'onto'}{'sumo'} = 'SUMO';
    $extres{'onto'}{'sumonew'} = 'SUMO-new';
    $extres{'onto'}{'sumoext'} = 'SUMO-ext';
    $extres{'wn'}{'wn21'} = 'Wordnet 2.1';
    $extres{'wn'}{'wn30'} = 'Wordnet 3.0';
    $extres{'wn'}{'hinwn'} = 'HindiWordnet';


our %statflags; # Ценность флагов статуса связей
    $statflags{"auto"} = "0"; $statflags{"good"} = "1"; $statflags{"manual"} = "4";
    $statflags{"monosemic"} = "1"; $statflags{"polysemic"} = "0";
    $statflags{"corrected"} = "1"; $statflags{"veccor"} = "1";
    $statflags{"1lang"} = "0"; $statflags{"2lang"} = "1"; $statflags{"3lang"} = "2";
    $statflags{"unknown"} = "0"; $statflags{"restored"} = "0";

our %invrels; # Список отношений, в пару которым создаем инверсные связи
$invrels{'rsn'} = '<-rsn-';
$invrels{'pof'} = '<-pof-'; # Отключить, если появится новое отношение в словаре.
$invrels{'icl'} = '<-icl-';
$invrels{'ins'} = '<-ins-';


our %cyrilliclng; # Коды языков с кириллической письменностью (для определения метки языка) 
    $cyrilliclng{'rus'} = ""; $cyrilliclng{'bel'} = ""; $cyrilliclng{'ukr'} = "";
our %alphabet; # Выражения для определения метки языка по набору знаков в строке (помогает отделить английский от языков с другой письменностью) Это не исчерпывающий набор знаков! 
    $alphabet{'eng'} = "[a-z]"; $alphabet{'rus'} = "[а-я]"; $alphabet{'bel'} = "[а-я]"; $alphabet{'ukr'} = "[а-я]"; $alphabet{'hin'} = "[\x{0900}=\x{097F}]";
our $suplng = "(unl|eng|rus|hin|fra|spa|vie|msa)"; # Скобки в этом выражении обязательны, для получения кода языка в переменной $1 !

our $disclaimer = '';
#our $disclaimer = '<!--
#This file is a part of a prototype version of the Common UNL Dictionary for the U++ consortium of researchers.
#
#This data comes under the terms of GPLv3 or CC-BY-NC-SA.
#
#Any amendments and additions must be made available with a notice for the U++ consortium, 
#which is free to merge them in the main development trunk or reject them. Other licensing terms 
#may be negotiated with the members of U++ consortium and developers of the dictionary.
#
#NOTE! The dictionary is still in the process of verification and development.
#
#This version of the Common UNL Dictionary was built using semi-automatic techniques of data transformation 
#with subsequent manual verification and correction. The main sources of semantic and linguistic data used 
#were Princeton Wordnet 2.1 & 3.0 and IEEE SUMO ontology. About 10 000 concepts, which represent most English 
#verbs, all conjuctions, particles and prepositions, have been created by hand.
#
#The dictionary provides mappings between UNL UWs, Wordnet synsets and SUMO terms. 
#The concepts are also linked with the dictionaries of several NL Processing systems, including ETAP-3 
#(IITP RAS, Moscow) and Ariane (GETALP LIG, Grenoble). The contents of these resources is not covered
#or in any way restricted by the terms of the licenses above. -->';

sub uwdetectpos ($) { # Определяем часть речи по UW
    my ($lex)=@_;

    if ($lex =~ m/ICL\>([A-Z\'\_\-\(\>\)]+[\>\<])*(DO|BE|OCCUR)(\,|\))/i) {
	return "v";
    } elsif ($lex =~ m/ICL\>([A-Z\'\_\-\(\>\)]+[\>\<])*ADJ(\,|\))/i) {
	return "a";
    } elsif ($lex =~ m/ICL\>([A-Z\'\_\-\(\>\)]+[\>\<])*HOW(\,|\)|\.|\:)/i and $lex =~ m/[\:\,\.\(]OBJ\>[A-Z]/i and $lex =~ m/[\:\,\.\(][AND|OR]\<[A-Z]/i) {
	return "conj";
    } elsif ($lex =~ m/ICL\>([A-Z\'\_\-\(\>\)]+[\>\<])*HOW(\,|\)|\.|\:)/i and $lex =~ m/[\:\,\.\(]OBJ\>[A-Z]/i) {
	return "pr";
    } elsif ($lex =~ m/ICL\>([A-Z\'\_\-\(\>\)]+[\>\<])*HOW(\,|\)|\.|\:)/i) {
	return "adv";
    } elsif ($lex =~ m/(ICL|IOF|POF)\>[A-Z\'\_\-\(\>\)]*(THING|INFORMATION|PERSON|PROPERTY|PROCESS|SURNAME|NAME|TIME|PLACE|CITY|LANGUAGE|NATIONALITY|ANIMAL|PLANT|ORGAN|GROUP|ORGANIZATION|ACTION|EVENT|QUANTITY|MONEY|CHARACTER|MATTER|STATE|OCCUPATION|TRADEMARK|QUALITY|AGREEMENT|PREPARATION|MEASURE|INSTITUTION|EXCHANGE|NUMBER|ABILITY|POWER|SKILL|WAY|TRADITION|UNIT|JOB|OBLIGATION|TAX|DOMAIN|PORPERTY|FORCE|ABSTRACT\+THING|AREA|PARSON|POSTURE|FALLING|OBJECT|ATTRIBUTE|MELODY|VERSION)(\,|\))/i) {
	return "n";
    };
    return '';
};


sub uwdetectanim ($) { # Определяем часть речи по UW
    my ($lex)=@_;

    if ($lex =~ m/(ICL|IOF)\>[A-Z\'\_\-\(\>\)]*(PERSON|SURNAME|NAME|CITY|NATIONALITY|ANIMAL|PLANT|ORGAN|GROUP|ORGANIZATION)(\,|\))/i) {return "anim"};
    return '';
};



sub uwnormalize ($) {
    my ($s) = @_;
    $s =~ s/</_/g;
    $s =~ s/>/_/g;
    return $s;
}

sub xmlnormalizelex ($) {
    my ($s) = @_;
    unless (defined $s) {$s = ''};
    $s =~ s/\'/_/g;
    $s =~ s/\"//g;
    $s = xmlnormalize($s);
    
    if (length($s) > 255) {print "too long\n$s\n";};
    
    return $s;
}

sub xmlnormalize ($) {
    my ($s) = @_;
    unless (defined $s) {$s = ''};
    $s =~ s/&(?!(amp|apos|quot|lt|gt);)/&amp;/g;
    $s =~ s/\'/&apos;/g;
    $s =~ s/\"/&quot;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    
    return $s;
}


################################################# Преобразование словаря UNL

sub cnvwnrel ($) { # Перевод меток отношений между единицами словаря UNL и прочими ресурсами в человеческий вид
    my ($s) = @_;

    if ($s eq '=' or $s eq '-') {$s = 'Same_as'}
    elsif ($s eq '<') {$s = 'Included_in'}
    elsif ($s eq '>') {$s = 'Includes'}
    elsif ($s eq '@') {$s = 'Instance_of'};
    return $s;
}

sub cnvsumorel ($) { # Перевод меток отношений между единицами словаря UNL и прочими ресурсами в человеческий вид
    my ($s) = @_;

    if ($s eq '=') {$s = 'Same_as'}
    elsif ($s eq '<') {$s = 'Subclass_of'}
    elsif ($s eq '>') {$s = 'Superclass_of'}
    elsif ($s eq '@') {$s = 'Instance_of'}
    elsif ($s eq '[') {$s = 'Disjoint_with'}
    elsif ($s eq ':') {$s = 'Not_same_as'};
    return $s;
}

sub parsewnlink ($$$$) {
    my ($s, $rel, $coord, $altcoord) = @_;
    
    foreach $pos (sort keys %{$s}) {
    foreach $offset (sort keys %{${$s}{$pos}}) {
	if (${$s}{$pos}{$offset}{'rel'} and ${$s}{$pos}{$offset}{'index'} and defined $offset) {
	    ${$rel} = ${$s}{$pos}{$offset}{'rel'};
	    ${$coord} = ${$s}{$pos}{$offset}{'index'};
	    ${$altcoord} = $offset;
	    return 1;
	}; # Возврат с первым результатом
    };
    };
    return 0;
}



###########################################################
###########################################################
###########################################################
###########################################################



###########################



sub getnlwfeat ($$$$$) { # Свойства слова
    my ($lngcode, $pos, $procname, $proc, $feats) = @_;

    #undef %{$feats};
    #${$feats}{'pos'}{$pos} = '';
    
    # определение переменных в зависимости от языка и процессора
    $morefeat = '';
    if ($lngcode eq 'rus' and $procname eq 'ETAP3') {
	$gender = ''; 
	$animacity = ''; 
	if ($proc =~ m/МУЖСК/) {${$feats}{'gender'}{'m'} = ''} elsif ($proc =~ m/ЖЕНСК/) {${$feats}{'gender'}{'f'} = ''} elsif ($proc =~ m/СРЕДН/) {${$feats}{'gender'}{'n'} = ''};
	if ($pos eq 'n' and $proc =~ m/ОДУШ/) {${$feats}{'animacity'}{'anim'} = ''} elsif ($pos eq 'n' and $proc) {${$feats}{'animacity'}{'inanim'} = ''};
    } elsif ($lngcode eq 'fra' and $procname eq 'Ariane') {
	$gender = ''; 
	if ($proc =~ m/GNR\(MAS\)/) {${$feats}{'gender'}{'m'} = ''} elsif ($proc =~ m/GNR\(FEM\)/) {${$feats}{'gender'}{'f'} = ''} elsif ($proc =~ m/GNR\(MAS,FEM\)/) {${$feats}{'gender'}{'m'} = ''; ${$feats}{'gender'}{'f'} = '';};
    } elsif ($lngcode eq 'hin' and $procname eq 'CFILT') {
	$gender = ''; 
	$animacity = ''; 
	if ($proc =~ m/(MALE|,M,)/) {${$feats}{'gender'}{'m'} = ''} elsif ($proc =~ m/(FEMALE|,F,)/) {${$feats}{'gender'}{'f'} = ''} elsif ($proc =~ m/,N,/) {${$feats}{'gender'}{'n'} = ''};
	if ($pos eq 'n' and $proc =~ m/ANIMT/) {${$feats}{'animacity'}{'anim'} = ''} elsif ($pos eq 'n' and $proc =~ m/INANI/) {${$feats}{'animacity'}{'inanim'} = ''};
    };
};

sub getnllexfeat ($$$$) { # Свойства специфичные для лекси (транзитивность и т.п.)
    my ($lngcode, $pos, $procname, $proc) = @_;

    # Доопределение переменных в зависимости от языка и процессора
    $morefeat = '';
    if ($lngcode eq 'eng' and $procname eq 'ETAP3') {
	$transitivity = ''; 
	if ($proc =~ m/TRANSIT/) {$transitivity = 'tr'};
	if ($transitivity) {$morefeat = "		<p:transitivity>".xmlnormalize($transitivity)."</p:transitivity>\n";};
    } elsif ($lngcode eq 'rus' and $procname eq 'ETAP3') {
	$gender = ''; 
	$animacity = ''; 
	$transitivity = ''; 
	if ($proc =~ m/МУЖСК/) {$gender = 'm'} elsif ($proc =~ m/ЖЕНСК/) {$gender = 'f'} elsif ($proc =~ m/СРЕДН/) {$gender = 'n'};
	if ($pos eq 'n' and $proc =~ m/ОДУШ/) {$animacity = 'anim'} elsif ($pos eq 'n' and $proc) {$animacity = 'inanim'};
	if ($proc =~ m/ТРАНЗИТ/) {$transitivity = 'tr'};
#	if ($gender) {$morefeat = "		<p:gender>".xmlnormalize($gender)."</p:gender>\n"};
#	if ($animacity) {$morefeat .= "		<p:animacity>".xmlnormalize($animacity)."</p:animacity>\n"};
	if ($transitivity) {$morefeat .= "		<p:transitivity>".xmlnormalize($transitivity)."</p:transitivity>\n"};
    } elsif ($lngcode eq 'fra' and $procname eq 'Ariane') {
	$gender = ''; 
	$transitivity = ''; 
	if ($proc =~ m/GNR\(MAS\)/) {$gender = "m"} elsif ($proc =~ m/GNR\(FEM\)/) {$gender = "f"} elsif ($proc =~ m/GNR\(MAS,FEM\)/) {$gender = "mf"};
#	if ($gender) {$morefeat = "		<p:gender>".xmlnormalize($gender)."</p:gender>\n"};
	if ($transitivity) {$morefeat .= "		<p:transitivity>".xmlnormalize($transitivity)."</p:transitivity>\n";};
    } elsif ($lngcode eq 'hin' and $procname eq 'CFILT') {
	$gender = ''; 
	$animacity = ''; 
	$transitivity = ''; 
	if ($proc =~ m/(MALE|,M,)/) {$gender = 'm'} elsif ($proc =~ m/(FEMALE|,F,)/) {$gender = 'f'} elsif ($proc =~ m/,N,/) {$gender = 'n'};
	if ($pos eq 'n' and $proc =~ m/ANIMT/) {$animacity = 'anim'} elsif ($pos eq 'n' and $proc =~ m/INANI/) {$animacity = 'inanim'};
	if ($proc =~ m/VLTN/) {$transitivity = 'tr'};
#	if ($gender) {$morefeat = "		<p:gender>".xmlnormalize($gender)."</p:gender>\n"};
#	if ($animacity) {$morefeat .= "		<p:animacity>".xmlnormalize($animacity)."</p:animacity>\n"};
	if ($transitivity) {$morefeat .= "		<p:transitivity>".xmlnormalize($transitivity)."</p:transitivity>\n"};
    };
    return $morefeat;
};

sub getproclnk ($$$$) { # Доопределение переменных в зависимости от языка и процессора
    my ($lngcode, $w, $procname, $proc) = @_;

    unless ($proc) {return ''};
    $prc = '';
    
    if ($lngcode and $procname) {
	if ($proc =~ m/^(.*)\:(.*)$/) {
	    $prc = "			<p:processor p:name=\"$procname\" p:access=\"Public\">
				<p:procref type=\"entry\" id=\"".xmlnormalize($1)."\" var=\"".xmlnormalize($2)."\" lang=\"".uc($lngcode)."\"/>
			</p:processor>\n";
	} else { # Если нет имени словарной статьи
	    $prc = "			<p:processor p:name=\"$procname\" p:access=\"Public\">
				<p:procref type=\"entry\" id=\"".xmlnormalize($w)."\" var=\"".xmlnormalize($proc)."\" lang=\"".uc($lngcode)."\"/>
			</p:processor>\n";
	};
    };
    return $prc;
};

#sub getprocname ($$) {
#    my ($lngcode, $proc) = @_;
#
#    # Сюда можно вставить определение названия процессора по ссылке, если будет язык с несколькими процессорами
#    if ($lngcode eq 'eng') {return 'ETAP3'}
#    elsif ($lngcode eq 'rus') {return 'ETAP3'}
#    elsif ($lngcode eq 'fra') {return 'Ariane'}
#    elsif ($lngcode eq 'hin') {return 'CFILT'};
#
#    return '';
#};


########################################################################

sub makeuwhistory ($) { # Старые версии UW
    my ($uw) = @_;
    my $out = '';
    my $luw;
#@{$pivot{$uw}{'unl'}{'history'}} = split($olduwdelim, $history)

    if (exists $pivot{$uw}{'unl'}{'history'}) {
	foreach $luw (@{$pivot{$uw}{'unl'}{'history'}}) {
	    $out .= "<k><opt>".xmlnormalize($luw)."</opt></k>";
	};
    };
    return $out;
# Старые версии UW (альтернативный способ для конверсии в Stardict)
#if (exists $pivot{$uw}{'history'}) {$out .= "<def cmt=\"Legacy forms\">
#    <b>Deprecated UW forms:</b>
#                    <c c=\"#696969\">".xmlnormalize(join(',', sort keys %{$pivot{$uw}{'history'}}))."</c>
#                </def>";
#};
};


sub makegr ($$$$) { # Грамм признаки слова
    ($sp,$lex,$lngcode,$vocable) = @_;
    my ($out, $feat, $featval);

    $out .= $sp."<def><gr>";
    foreach $feat (sort {$b cmp $a} keys %{$lex{$lngcode}{$vocable}{'feat'}}) {
	foreach $featval (sort keys %{$lex{$lngcode}{$vocable}{'feat'}{$feat}}) {
	    $out .= "<abbr>".xmlnormalize($featval)."</abbr>. ";
	};
    };
    $out .= "</gr></def>";
    return $out;
};

sub makeglosses ($$) { # Глоссы
    my ($sp, $uw) = @_;
    my ($out, $c, $lngcodecomm);
    my %gloss;

    parsegloss($pivot{$uw}{'unl'}{'comm'}, $pivot{$uw}{'unl'}{'ex'}, \%gloss);
    $out .= $sp."<def cmt=\"Glosses\"><b>Definitions:</b>\n";
    foreach $lngcodecomm (sort keys %gloss) { # Вывод комментариев на всех языках
	foreach $c (sort keys %{$gloss{$lngcodecomm}}) {
	    if ($c or $gloss{$lngcodecomm}{$c}) {
		$out .= $sp."   <def cmt=\"".$lngcodecomm."\">";
		if ($c) {$out .= xmlnormalize($c);};
		if ($gloss{$lngcodecomm}{$c}) {$out .= "\n".$sp."   <ex>".xmlnormalize($gloss{$lngcodecomm}{$c})."</ex>";};
		$out .= "</def>\n"; # one definition
	    };
	};
    }; # all languages
    $out .= $sp."</def>\n"; # all glosses
    return $out;
};

sub makemeta ($$) {
    my ($sp, $uw) = @_;
    my $out;

    $out .= $sp."   <def cmt=\"Meta\">";
    if ($pivot{$uw}{'unl'}{'freq'}) {$out .= "<def>Frequency: ".xmlnormalize($pivot{$uw}{'unl'}{'freq'})."</def>     ";};
    $out .= "<def>Reference language: ".xmlnormalize($pivot{$uw}{'unl'}{'srclang'})."</def>     ";
    $out .= "<def>Status: ".xmlnormalize($pivot{$uw}{'unl'}{'status'})."</def>     ";
    $out .= "<def>UW source: ".xmlnormalize($pivot{$uw}{'unl'}{'author'})."</def>     ";
    $out .= "</def>\n\n";
    return $out;
};

sub makeuwlinks ($$) { # Связанные UW
    my ($sp, $uw) = @_;
    my $uwb;
    my $out = '';
    my %lnks;
    
    foreach $rel (keys %uwlinks) {
    foreach $uwb (keys %{$uwlinks{$rel}{$uw}}) {
	$lnks{'rels'}{$rel}{$uwb} = $uwlinks{$rel}{$uw}{$uwb};
    };
    };

    # Инверсные ссылки
    foreach my $invrel (sort keys %invrels) { 
	if (exists $invuwlinks{$invrel}{$uw}) {
	    foreach $uwb (sort keys %{$invuwlinks{$invrel}{$uw}}) {
		my $invlabel = xmlnormalize($invrels{$invrel});
		$lnks{'rels'}{$invlabel}{$uwb} = $invuwlinks{$invrel}{$uw}{$uwb};
	    };
	};
    };

    if (exists $lnks{'rels'}) {
	$out .= $sp."<def cmt=\"Links\"><b>Links to other UWs:</b>\n";

	foreach $rel (sort keys %{$lnks{'rels'}}) {
	foreach $uwb (sort keys %{$lnks{'rels'}{$rel}}) {
	
	    if ($lnks{'rels'}{$rel}{$uwb}) {
		#$out .= $sp."   <c c=\"#696969\">".xmlnormalize(join(',', sort keys %{$pivot{$uw}{'history'}}))."</c>";
		$out .= $sp."   <def><b><c c=\"#696969\">$rel:</c>      <kref>".xmlnormalize("$uwb")."</kref>   ".xmlnormalize($lnks{'rels'}{$rel}{$uwb})."</b></def>\n";
	    } else {
		#$out .= $sp."   <c c=\"#696969\">".xmlnormalize(join(',', sort keys %{$pivot{$uw}{'history'}}))."</c>";
		$out .= $sp."   <def><b><c c=\"#696969\">$rel:</c>      <kref>".xmlnormalize("$uwb")."</kref></b></def>\n";
	    };
	};
	};
	$out .= $sp."</def>\n";
    };

    return $out;


# Сем. ссылки
#if (exists $pivot{$uw}{'unl'}{'links'}) {$out .= "<def cmt=\"Semantic links\">
#                <b>Semantic links:</b>
#";
#foreach $lnk (sort keys %{$pivot{$uw}{'unl'}{'links'}}) {
#$out .= "                <sr type=\"hpr\">".xmlnormalize($lnk).": ";
#foreach $luw (sort keys %{$pivot{$uw}{'unl'}{'links'}{$lnk}}) {
#$out .= "<kref>".xmlnormalize($luw)."</kref>"
#};
#$out .= "</sr>
#";};
#$out .= "                </def>";};
#                    <sr type=\"hpr\">icl: <kref>XXX</kref></sr>
#                    <sr type=\"syn\">equ: <kref>XXX</kref></sr>
#                    <sr type=\"ant\">ant: <kref>XXX</kref></sr>
#                    <sr type=\"ent\">com: <kref>XXX</kref></sr>


};

sub sortrel {
    if ($a eq 'syn') {return -1} 
    elsif ($a eq 'ant' and $b ne 'syn') {return -1}
    else {return $a cmp $b};
};

sub makewordlinks ($$$$) { # блок ссылок на связанные слова
    my ($sp, $uw, $lngcode, $w) = @_;
    my ($uwb, $uwbtr, $lnkstr);
    my $out = '';
    my %lnks;
    my %wrds;
    my %reltr;
    
$reltr{'rus'}{'syn'} = 'Синонимы';
$reltr{'rus'}{'ant'} = 'Антонимы';
$reltr{'rus'}{'icl'} = 'Гиперонимы';
$reltr{'rus'}{'pof'} = 'Часть';
$reltr{'rus'}{'ins'} = 'Инструмент для';
$reltr{'rus'}{'agt'} = 'Деятель';
$reltr{'rus'}{'obj'} = 'Объект';
$reltr{'rus'}{'pur'} = 'Цель';
$reltr{'rus'}{'com'} = 'Ассоциации';
$reltr{'rus'}{'pos'} = 'Владелец';
$reltr{'rus'}{'met'} = 'Метод';
$reltr{'rus'}{'scn'} = 'Сцена';
$reltr{'rus'}{'rec'} = 'Реципиент';
$reltr{'rus'}{'rsn'} = 'Причина';
$reltr{'rus'}{'<-rsn-'} = 'Результат';
$reltr{'rus'}{'<-pof-'} = 'Имеет части'; # Отключить, если появится новое отношение в словаре.
$reltr{'rus'}{'<-icl-'} = 'Гипонимы';
$reltr{'rus'}{'<-ins-'} = 'Инструмент';

$reltr{'*'}{'syn'} = 'Synonyms';
$reltr{'*'}{'ant'} = 'Antonyms';
$reltr{'*'}{'icl'} = 'Hypernym';
$reltr{'*'}{'pof'} = 'PartOf';
$reltr{'*'}{'ins'} = 'InstrumentOf';
$reltr{'*'}{'agt'} = 'Agent';
$reltr{'*'}{'obj'} = 'Patient';
$reltr{'*'}{'pur'} = 'Purpose';
$reltr{'*'}{'com'} = 'Association';
$reltr{'*'}{'pos'} = 'Possessor';
$reltr{'*'}{'met'} = 'Method';
$reltr{'*'}{'scn'} = 'Frame';
$reltr{'*'}{'rec'} = 'Recipient';
$reltr{'*'}{'rsn'} = 'Reason';
$reltr{'*'}{'<-rsn-'} = 'Result';
$reltr{'*'}{'<-pof-'} = 'HasPart'; # Отключить, если появится новое отношение в словаре.
$reltr{'*'}{'<-icl-'} = 'Hyponyms';
$reltr{'*'}{'<-ins-'} = 'HasInstrument';




    foreach $rel (sort keys %uwlinks) {
    foreach $uwb (sort keys %{$uwlinks{$rel}{$uw}}) {
	$lnks{'rels'}{$rel}{$uwb} = '';
	foreach $uwbtr (sort keys %{$pivot{$uwb}{'trans'}{$lngcode}} ) {
	    if ($uwbtr and $uwbtr ne $w) {
		if ($rel eq 'equ' or $rel eq 'cnt') { # Слияние equ и cnt 
		    $wrds{'syn'}{$uwbtr} = '';
		} else { # Прочие ссылки
			$wrds{$rel}{$uwbtr} = $lnks{'rels'}{$rel}{$uwb};
		};
	    };
	};
    };
    };

    # Инверсные ссылки
    foreach my $invrel (sort keys %invrels) { 
	if (exists $invuwlinks{$invrel}{$uw}) {
	    foreach $uwb (sort keys %{$invuwlinks{$invrel}{$uw}}) {
		my $invlabel = $invrels{$invrel};
		$lnks{'rels'}{$invlabel}{$uwb} = '';

		foreach $uwbtr (sort keys %{$pivot{$uwb}{'trans'}{$lngcode}} ) {
		    if ($uwbtr and $uwbtr ne $w) {
			$wrds{$invlabel}{$uwbtr} = $lnks{'rels'}{$invlabel}{$uwb};
		    };
		};

	    };
	};
    };

    if (hashknum(\%wrds)) {
    #if (exists $wrds{'syn'} or exists $wrds{'ant'}) {} # Если есть синонимы-антонимы
	$out .= $sp."<def cmt=\"Links\">";

	foreach $rel (sort sortrel keys %wrds) {
	    $relstr = $rel;
	    if (exists $reltr{$lngcode}{$rel}) {$relstr = $reltr{$lngcode}{$rel}} # Подстановка локализованного названия отношения
	     elsif (exists $reltr{'*'}{$rel}) {$relstr = $reltr{'*'}{$rel}}; # Подстановка расшифрованного названия отношения
	
	    $out .= $sp."<b>$relstr:</b>";
	    foreach $uwbtr (sort keys %{$wrds{$rel}}) {$lnkstr = append($lnkstr, " <kref>$uwbtr</kref>", ',')};
	    $out .= "$lnkstr\n"; undef $lnkstr;
	};

#	if (hashknum(\%{$wrds{'syn'}})) {
#	    $out .= $sp."<b>Synonyms:</b>";
#	    foreach $uwbtr (sort keys %{$wrds{'syn'}}) {$lnkstr = append($lnkstr, " <kref>$uwbtr</kref>", ',')};
#	    $out .= "$lnkstr\n"; undef $lnkstr;
#	};
#	if (hashknum(\%{$wrds{'ant'}})) {
#	    $out .= $sp."<b>Antonyms:</b>";
#	    foreach $uwbtr (sort keys %{$wrds{'ant'}}) {$lnkstr = append($lnkstr, " <kref>$uwbtr</kref>", ',')};
#	    $out .= "$lnkstr\n"; undef $lnkstr;
#	};
	$out .= $sp."</def>\n";
    };
    return $out;
};


sub makeextlinks ($$) { # Ссылки на внешние ресурсы
    my ($sp, $uw) = @_;
    my $headtxt = "<def cmt=\"Resource links\"> <b>Links to other resources:</b>\n";
    my $headflg = 0; 
    my $out = '';

    foreach $key (sort keys %{$extres{'onto'}}) { # Все имеющиеся онтологии
	if (exists $pivot{$uw}{'unl'}{$key}) { #(hashknum(\%{$pivot{$uw}{'unl'}{$key}}))
	    unless ($headflg) {$out .= $sp.$headtxt; $headflg = 1}; # Если нет шапки списка ссылок - добавить ее

	    $out .= $sp."   <def>".$extres{'onto'}{$key}.":"; # Вставляем человеческое название
	    my ($rel, $term);
	    foreach $rel (sort keys %{$pivot{$uw}{'unl'}{$key}}) {
	    foreach $term (sort keys %{$pivot{$uw}{'unl'}{$key}{$rel}}) {
		$out .= " ".xmlnormalize(cnvsumorel($rel))." <i>".xmlnormalize($term)."</i>";
	    };
	    };
	    $out .= "</def>\n";
	};
    };

    foreach $key (sort keys %{$extres{'wn'}}) {
	my ($wnrel, $wncoord, $wnaltcoord);
	if (parsewnlink(\%{$pivot{$uw}{'unl'}{$key}}, \$wnrel, \$wncoord, \$wnaltcoord)) {
	    unless ($headflg) {$out .= $sp.$headtxt; $headflg = 1}; # Если нет шапки списка ссылок - добавить ее

	    $out .= $sp."   <def>".$extres{'wn'}{$key}.": ".xmlnormalize(cnvwnrel($wnrel))." <i>".xmlnormalize(lc($wncoord))."</i> (<i>".xmlnormalize($wnaltcoord)."</i>)</def>\n";
	};
    };
    
    if ($headflg) {$out .= $sp."</def>\n"};
    return $out;
}; 


sub maketrans ($$$) { # Translations
    my ($sp, $uw, $lngcode) = @_;
    my ($lngcodetr, $feat, $featval, $lexietr, $vocabletr);
    my $out = '';
    
    if (exists $pivot{$uw}{'lexies'}) {
	$out .= $sp."<def cmt=\"Translations\"><b>Other natural Languages:</b>\n";

	foreach $lngcodetr (reverse sort keys %{$pivot{$uw}{'lexies'}}) {
	    unless ($lngcode and $lngcodetr eq $lngcode) {

		$out .= $sp."<def cmt=\"".xmlnormalize($lngcodetr)."\"><c c=\"#FF0000\"><b>".xmlnormalize($lngcodetr).":</b></c>";
		foreach $lexietr (sort keys %{$pivot{$uw}{'lexies'}{$lngcodetr}}) {
		    $vocabletr = $pivot{$uw}{'lexies'}{$lngcodetr}{$lexietr};
		    $out .= $sp."         <def><dtrn><big><b>".xmlnormalize($lex{$lngcodetr}{$vocabletr}{'lemma'})."</b></big></dtrn>";

		    $out .= "         <gr>";
		    # Грамм признаки слова
		    foreach $feat (sort {$b cmp $a} keys %{$lex{$lngcodetr}{$vocabletr}{'feat'}}) {
			foreach $featval (sort keys %{$lex{$lngcodetr}{$vocabletr}{'feat'}{$feat}}) {
			    $out .= "<abbr>".xmlnormalize($featval)."</abbr>. ";
			};
		    };
		    #if ($lex{$lngcode}{$vocable}{'feat'}{'pos'}) {$out .= "<abbr>".xmlnormalize($lex{$lngcode}{$vocable}{'feat'}{'pos'})."</abbr>." };
		    $out .= "</gr>";

		    $out .= "         <co>Status: ".xmlnormalize($lex{$lngcodetr}{$vocabletr}{'lex'}{$lexietr}{'uw'}{$uw}{'stat'})."</co>         ";
		    if ($lex{$lngcodetr}{$vocabletr}{'lex'}{$lexietr}{'proc'} and $lex{$lngcodetr}{$vocabletr}{'lex'}{$lexietr}{'procname'}) {
			$out .= $sp."<def cmt=\"MT systems\">";
			$out .= "<def cmt=\"".xmlnormalize($lex{$lngcodetr}{$vocabletr}{'lex'}{$lexietr}{'procname'})."\">".xmlnormalize($lex{$lngcodetr}{$vocabletr}{'lex'}{$lexietr}{'procname'}).": <i>".xmlnormalize($lex{$lngcodetr}{$vocabletr}{'lex'}{$lexietr}{'proc'})."</i></def>";
			$out .= "</def>";
		    };
		    $out .= $sp."</def>\n";
		};
		$out .= $sp."</def>";
	    };
	};
	$out .= $sp."</def>\n";
    };
    return $out;
};

########################################################

sub outunlvolhead { # вывод заголовка

return "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>
<!DOCTYPE xdxf SYSTEM \"https://raw.github.com/soshial/xdxf_makedict/master/format_standard/xdxf_strict.dtd\">
<xdxf lang_from=\"UNL\" lang_to=\"ALL\" format=\"logical\">
    <meta_info>
        <full_name>U++ Common UNL Dictionary of Concepts</full_name>
        <description>U++ version of the common UNL dictionary. Published under GPLv3+ and CC-BY-SA</description>
        <authors>
          <author role=\"maintenance\">Viacheslav Dikonov</author>
          <author role=\"Russian lexicon\">Viacheslav Dikonov</author>
        </authors>
        <file_ver>0.6</file_ver>
        <creation_date>26-05-2013</creation_date>
        <dict_src_url>".xmlnormalize('http://atoum.imag.fr/geta/User/services/pivax/data/')."</dict_src_url>

        <abbreviations>
          <abbr_def type=\"grm\"><abbr_k>n</abbr_k> <abbr_v>noun</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>v</abbr_k> <abbr_v>verb</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>adj</abbr_k> <abbr_k>a.</abbr_k> <abbr_v>adjective</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>adv</abbr_k> <abbr_v>adverb</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>prep</abbr_k> <abbr_v>preposition</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>conj</abbr_k> <abbr_v>conjunction</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>m</abbr_k> <abbr_v>male</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>f</abbr_k> <abbr_v>female</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>n</abbr_k> <abbr_v>neutral</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>mf</abbr_k><abbr_k>fm</abbr_k> <abbr_v>double gender</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>anim</abbr_k> <abbr_v>animous</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>inanim</abbr_k> <abbr_v>inanimous</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>pl</abbr_k> <abbr_v>plural</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>sg</abbr_k> <abbr_v>singular</abbr_v></abbr_def>
        </abbreviations>

    </meta_info>

    <lexicon>
";}

sub outnlvolhead ($) { # вывод заголовка
    my ($lngcode) = @_;
    
    $lngcode = uc($lngcode);

return "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>
<!DOCTYPE xdxf SYSTEM \"https://raw.github.com/soshial/xdxf_makedict/master/format_standard/xdxf_strict.dtd\">
<xdxf lang_from=\"".$lngcode."\" lang_to=\"UNL\" format=\"logical\">
    <meta_info>
        <full_name>".$lngcode." to U++UNL Dictionary</full_name>
        <description>U++ version of ".$lngcode." to UNL dictionary. Published under GPLv3+ and CC-BY-SA</description>
        <file_ver>0.6</file_ver>
        <creation_date>26-05-2013</creation_date>
        <dict_src_url>".xmlnormalize('http://atoum.imag.fr/geta/User/services/pivax/data/')."</dict_src_url>

        <abbreviations>
          <abbr_def type=\"grm\"><abbr_k>n</abbr_k> <abbr_v>noun</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>v</abbr_k> <abbr_v>verb</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>adj</abbr_k> <abbr_k>a.</abbr_k> <abbr_v>adjective</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>adv</abbr_k> <abbr_v>adverb</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>prep</abbr_k> <abbr_v>preposition</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>conj</abbr_k> <abbr_v>conjunction</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>m</abbr_k> <abbr_v>male</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>f</abbr_k> <abbr_v>female</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>n</abbr_k> <abbr_v>neutral</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>mf</abbr_k><abbr_k>fm</abbr_k> <abbr_v>double gender</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>anim</abbr_k> <abbr_v>animous</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>inanim</abbr_k> <abbr_v>inanimous</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>pl</abbr_k> <abbr_v>plural</abbr_v></abbr_def>
          <abbr_def type=\"grm\"><abbr_k>sg</abbr_k> <abbr_v>singular</abbr_v></abbr_def>
        </abbreviations>

    </meta_info>

    <lexicon>
";}


sub outvolfoot { # вывод заголовка
return "    </lexicon>
</xdxf>
";
}


sub outunlvolitem ($) { # вывод 1 элемента
    my ($uw) = @_;
    my ($hw, $rest, $wn21rel, $wn21coord, $wn21altcoord, $wn30rel, $wn30coord, $wn30altcoord, $sumorel, $sumoterm, $h, $lnk, $luw, $lngcode, $lexie, $feat, $featval);
    my $sp = '                ';
    my $out;

    if ( $uw =~ m/(.*?)(\(.*)/ ) {$hw = $1; $rest = $2} else {$hw = $uw; $rest = ''};
#            <k>".xmlnormalize($hw)."<opt>".xmlnormalize($rest)."</opt></k>";

$out = "
        <ar>
            <b><big><k>".xmlnormalize($uw)."</k></big></b><k>".xmlnormalize($hw)."<opt>".xmlnormalize($rest)."</opt></k>";
	    $out .= makeuwhistory($uw); # Добавить старые формы UW
	    $out .= "\n".$sp."<def>";

	    $out .= makeuwlinks($sp, $uw);
	    $out .= makeglosses($sp, $uw);
	    $out .= makemeta($sp, $uw);
	    $out .= makeextlinks($sp, $uw);
	    $out .= maketrans($sp, $uw, $lngcode);

# close tags
$out .= "            </def>
        </ar>
";

$out =~ s/\>[ \t]+\</> </g;
return $out;
}


sub makepivotxdxf { # вывод тома UNL
    my $uw;
    my $voltxt = '';
    my $c = 0;

    open (OUT, "> $dictname-unl.xdxf");
    print OUT encode $sysencoding, outunlvolhead;
    foreach $uw (sort keys %pivot) {
	$voltxt .= outunlvolitem($uw);
	$c++;
	if ($c eq 1000) {print OUT encode $sysencoding, $voltxt; $voltxt = ''; $c = 0};
    };
    print OUT encode $sysencoding, $voltxt; undef $voltxt;
    print OUT encode $sysencoding, outvolfoot;
    close OUT;
}


sub outnlvolitem ($$) { # вывод 1 элемента
    my ($lngcode, $vocable) = @_;
    #my ($rest, $wn21rel, $wn21coord, $wn21altcoord, $wn30rel, $wn30coord, $wn30altcoord, $sumorel, $sumoterm, $h, $lnk, $luw, $lngcode, $lexie, $feat, $featval);
    my $sp = '                ';
    my $out;

    $out = "\n        <ar>\n            ";
    $out .= "<b><big><k>".xmlnormalize($lex{$lngcode}{$vocable}{'lemma'})."</k></big></b>";
    $out .= "<def>";
    $out .= makegr($sp, $lex, $lngcode, $vocable);

    # Лекси
    foreach $lexie (sort keys %{$lex{$lngcode}{$vocable}{'lex'}}) {
	$out .= $sp."<def>\n";

	# Процессор для лекси
	if ($lex{$lngcode}{$vocable}{'lex'}{$lexie}{'proc'} and $lex{$lngcode}{$vocable}{'lex'}{$lexie}{'procname'}) {
	    $out .= "\n<def cmt=\"MT systems\">";
	    $out .= "<def cmt=\"".xmlnormalize($lex{$lngcode}{$vocable}{'lex'}{$lexie}{'procname'})."\">".xmlnormalize($lex{$lngcode}{$vocable}{'lex'}{$lexie}{'procname'}).": <i>".xmlnormalize($lex{$lngcode}{$vocable}{'lex'}{$lexie}{'proc'})."</i></def>";
	    $out .= "</def>";
	};

	foreach $uw (sort keys %{$lex{$lngcode}{$vocable}{'lex'}{$lexie}{'uw'}}) {
	    $out .= "\n                    <def>";
	    $out .= "\n    <dtrn><big><b>".xmlnormalize($uw)."</b></big></dtrn>\n\n";

	    # Глоссы
	    $out .= makeglosses($sp, $uw);
	    $out .= makemeta($sp, $uw);
	    $out .= makewordlinks($sp, $uw, $lngcode, $lex{$lngcode}{$vocable}{'lemma'});
	    $out .= makeextlinks($sp, $uw);
	    $out .= maketrans($sp, $uw, $lngcode);

	    # close UW
	    $out .= "                    </def>"; # uw
	};
	
	$out .= $sp."</def>\n"; # lexie
    };

    # close tags
    $out .= "            </def>\n        </ar>\n";
    $out =~ s/\>[ \t]+\</> </g;
    return $out;
}



#	    # ГЛОССЫ
#	    if ($comm =~ m/^(...)\:/) {$lngcode = $1} else {$lngcode = 'eng'}; # Если в комментарии не указан язык, то он Соответствует языку глоссов в томе UNL (взятых из WN)

#	    $pivot{$uw}{'freq'} = $freq;
#	    $pivot{$uw}{'status'} = $status;
#	    $pivot{$uw}{'author'} = $author;
#	    $pivot{$uw}{'wn21'} = $wn21;
#	    $pivot{$uw}{'wn30'} = $wn30;
#	    $pivot{$uw}{'sumo'} = $sumo;
#	    $pivot{$uw}{'srclang'} = $srclang;
#	    $pivot{$uw}{'lexies'}{$lngcode}{$lexie} = $vocable;


#		$lex{$lngcode}{$vocable}{'lemma'} = $w;
#		$lex{$lngcode}{$vocable}{'feat'}{'pos'} = $pos; # Берется из специального поля, которое олжно быть заполнено
#		#getnlwfeat($lngcode, $pos, $procname, $proc, \%{$lex{$lngcode}{$vocable}{'feat'}}); # Сбор свойств "лекси", которые статичны для слова
#		foreach $feat (keys %feats) {$lex{$lngcode}{$vocable}{'feat'}{$feat} = $feats{$feat}};
#		$lex{$lngcode}{$vocable}{'lex'}{$lexie}{'procname'} = $procname;
#		$lex{$lngcode}{$vocable}{'lex'}{$lexie}{'proc'} = $proc;
#		$lex{$lngcode}{$vocable}{'lex'}{$lexie}{'uw'}{$uw}{'stat'} = $status;

#	    $pivot{$uw1}{'unl'}{'links'}{$lnk}{$uw2} = $weight;





sub makenlxdxf {
    my $uw;
    my $voltxt = '';
    my $c = 0;

    foreach $lngcode (sort keys %lex) {
	print "Writing $lngcode dictionary...\n";
	open (OUT, "> $dictname-$lngcode.xdxf");
	print OUT encode $sysencoding, outnlvolhead($lngcode);
	foreach $vocable (sort keys %{$lex{$lngcode}}) {
	    $voltxt .= outnlvolitem($lngcode, $vocable);
	    $c++;
	    if ($c eq 1000) {print OUT encode $sysencoding, $voltxt; $voltxt = ''; $c = 0};
	    #print OUT encode $sysencoding, outnlvolitem($lngcode, $vocable);
	};
	print OUT encode $sysencoding, $voltxt; undef $voltxt;
	print OUT encode $sysencoding, outvolfoot;
	close OUT;
    };
}




###########################################################################
# Общеполезные функции
###########################################################################

sub logmsg ($$) {
    my ($s, $type) = @_;
    if ($type eq 'status') {
	print encode $sysencoding, "$s\n";
    } elsif ($type eq 'sys') {
	print encode $sysencoding, "ERROR: $s\n";
    } else { # 'data'
	print encode $sysencoding, "	$s\n";
    };
}

sub setencoding { # Detect locale and set output encoding if possible
    my $syslocale = setlocale(LC_CTYPE);

    if ( $syslocale =~ m/\./ ) { 
	($sysencoding = $syslocale) =~ s/.*\.//; 
    } else {$sysencoding = 'utf8'}; # Если кодировка не определяется, использовать UTF8
}


sub hashknum ($) {
    my ($h) = @_;
    my @a = keys %{$h};
    return $#a + 1;
}

sub append ($$$) {
    my ($s1, $s2, $delim) = @_;
    if ($s1) {$s1 .= $delim} else {$s1 = ''};
    if ($s2) {$s1 .= $s2};
    return $s1;
};

sub fixuw ($) {
    my ($uw) = @_;
    if (defined $uw) {
	$uw =~ s/\$/_/g;
	$uw =~ s/\:/,/g;
	$uw =~ s/\+//g;
	$uw =~ s/С/c/gi;
	#$uw = lc($uw);
    } else {$uw = ''};
    return $uw;
}

sub etapuwtonormal ($) {
    my ($uw) = @_;
    if (defined $uw) {
	$uw = lc($uw);
	$uw =~ s/;/,/g; $uw =~ s/\{/\(/g; $uw =~ s/\}/\)/g;
    } else {$uw = ''};
    return $uw;
}

sub normaluwtoetap ($) {
    my ($uw) = @_;
    if (defined $uw) {
	$uw = uc($uw);
	$uw =~ s/,/;/g; $uw =~ s/\(/\{/g; $uw =~ s/\)/\}/g;
    } else {$uw = ''};
    return $uw;
}


############################################################################
# Функции для работы с комментариями UW 
############################################################################

sub parseglstr ($$$) { # Разбор одной цепочки вида <lng:>s1|lng:s2|...
    my ($s, $chash, $lhash) = @_;
    my (@lst, $c, $subc, @sublst);
    
    unless ($s) {push(@lst, '')} else {@lst = split('\|', $s)}; # Пустой комментарий/пример возможен

    foreach $c (@lst) { # Каждый комментарий в цепочке
	$c =~ s/^\s+//;
	
	# Определение языка
	if ($c =~ s/^$suplng\://) { # Отделение метки языка
	    $l = $1;
	    while ($c =~ m/^$suplng\:/) {$c =~ s/^$suplng\://}; # стирание повторяющихся меток языка
	} else {
	    if ($c =~ m/$alphabet{'rus'}/i) {$l = 'rus'}
	    elsif ($c =~ m/$alphabet{'hin'}/i) {$l = 'hin'}
	    elsif ($c =~ m/$alphabet{'eng'}/i) {$l = 'eng'}; # Вся кириллица - русский, деванагари - хинди, латиница - английский. Ошибки легко могут быть!
	    $l = ''; # Умолчание
	};
	
	# Сбор списка комментариев для языка $l
	undef @sublst;
	if (exists ${$chash}{$l}) { push(@sublst, @{${$chash}{$l}}) }; # В переданном списке уже могут быть данные от прошлой итерации, если на входе несколько $c с одним языком

	foreach $subc (split(/$glosssubstrdelim/, $c)) { # Перебор подстрок. Сохраняется взаимный порядок
	    $subc =~ s/^\s+//; $subc =~ s/\s+$//;
	    my $f = 0;
	    foreach (@sublst) {if (m/^\s*\Q$subc\E\s*$/i) {$f = 1};}; # $subc - повтор уже имеющейся в @sublst строчки (без учета регистра)?
	    unless ($f) {push(@sublst, $subc)}; # если не повтор, то добавить
	};

	#push(@{${$chash}{$l}}, @sublst);
	@{${$chash}{$l}} = @sublst;
	${$lhash}{$l}='';  # lhash - список языков в строчке
    };
};

sub parsegloss($$$) { # Разбор списка разноязычных комментариев к UW 
    my ($commstr, $exstr, $lst) = @_;
    my (%comms, %exs, %lngs); # {lng} = @s1,s2
    my ($c, $e, $l);

    foreach $l (keys %{$lst}) {
	$lngs{$l} = '';
	foreach $c (keys %{${$lst}{$l}}) {
	    push(@{$comms{$l}}, split(/$glosssubstrdelim/, $c));
	    push(@{$exs{$l}}, split(/$glosssubstrdelim/, ${$lst}{$l}{$c}));
	};
    };
    undef %{$lst};

    parseglstr ($commstr, \%comms, \%lngs); # Разбор каждой из строчек порознь на списки строк по языкам
    parseglstr ($exstr, \%exs, \%lngs);

    foreach $l (sort keys %lngs) { # Перебор всех найденных языков
	if (exists $comms{$l}) { # На этом языке есть комментарии
	    if (exists $exs{$l}) { # Есть примеры
		${$lst}{$l}{join($glosssubstrdelim, @{$comms{$l}}) } = join($glosssubstrdelim, @{$exs{$l}});
	    } else { # Нет примеров
		${$lst}{$l}{join($glosssubstrdelim, @{$comms{$l}}) } = '';
	    };
	} else { # Комментария на этом языке нет
	    if (exists $exs{$l}) { #  но есть примеры
		${$lst}{$l}{''} = join($glosssubstrdelim, @{$exs{$l}});
	    };
	};
	
    };

#    if (hashknum(\%{${$lst}{''}}) and exists ${$lst}{'eng'}) {delete ${$lst}{'eng'}}; # Если есть два английских глосса
};

sub filtergloss ($$$) { # Оставить только заданный язык (а если его нет, то можно принять дежурный английский из WN)
    my ($lst, $lng, $accepteng) = @_;
    my %tmp;
    
    %tmp = %{$lst}; 
    undef %{$lst};
    if (exists $tmp{$lng}) {
	${$lst}{$lng} = $tmp{$lng};
    } elsif ($accepteng and exists $tmp{''}) {
	${$lst}{''} = $tmp{''};
    } elsif ($accepteng and exists $tmp{'eng'}) {
	${$lst}{'eng'} = $tmp{'eng'};
    };
}

sub append2 ($$$$$$) { # Сборка строк комментариев и примеров с соблюдением парности
    my ($sc1, $c2, $se1, $e2, $delim, $lng) = @_;
    my ($c1, $e1);

    $c1 = ${$sc1}; $e1 = ${$se1};
    unless (defined $c1) {$c1 = ''}; unless (defined $e1) {$e1 = ''};
    unless (defined $c2) {$c2 = ''}; unless (defined $e2) {$e2 = ''};

    if ($c2 or $e2) { # Если глосс2 не пустой, то приклеить его к глоссу1
	if ($c1 or $e1) {$c1 .= $delim; $e1 .= $delim}; # Добавить разделители, если глосс1 не пустой, и глосс2 тоже не пустой
	if ($lng and $c2) {$c2 = "$lng:$c2"}; # Добавить метку языка
	if ($lng and $e2) {$e2 = "$lng:$e2"};
	$c1 .= $c2; $e1 .= $e2;
    };
    ${$sc1} = $c1; ${$se1} = $e1; # Вывод
};


sub makegloss($$$) { # Сделать из списка комментариев строку
    my ($lst, $commstr, $exstr) = @_;
    my ($lng, $c, $rc, $re);

    foreach $lng (sort keys %{$lst}) { # Перебор языков в списке глоссов
	foreach $c (sort keys %{${$lst}{$lng}}) { 
		append2(\$rc, "$c", \$re, "${$lst}{$lng}{$c}", "\|", $lng);
	};
    };
    $rc =~ s/\|+$//; # Убираем лишние разделители с конца
    $re =~ s/\|+$//;

    ${$commstr} = $rc;
    ${$exstr} = $re;
};





###########################################################################
# Чтение и записть общего словаря
###########################################################################


sub readvols { # Чтение томов в определенном порядке
    my $name;
    my ($procname, $lngcode, $vol);

    if (exists $volslist{'unl'}{'uw'}) { # Прочесть список сем. связей между UW
	foreach $vol (sort keys %{$volslist{'unl'}{'uw'}}) {
	    readunlvol($volslist{'unl'}{'uw'}{$vol}{'path'}); # Анализировать UNL часть
	};
    } else {logmsg("Unable to find the master UNL volume \"dict-unl.csv\". Cannot continue.", 'sys'); exit};

    if (exists $volslist{'unl'}{'links'}) { # Прочесть список сем. связей между UW
	foreach $vol (sort keys %{$volslist{'unl'}{'links'}}) {
	    readlnkvol($volslist{'unl'}{'links'}{$vol}{'path'});
	};
    };

    if (exists $volslist{'ext'}) { # Прочесть список сем. связей между UW и внешними ресурсами
	foreach $key (sort keys %{$volslist{'ext'}}) {
	    foreach $vol (sort keys %{$volslist{'ext'}{$key}}) {
		if (exists $extres{'onto'}{$key}) {readontolnkvol($volslist{'ext'}{$key}{$vol}{'path'}, $key, 0)} # Ссылки на онтологии
		elsif (exists $extres{'wn'}{$key}) {readwnlnkvol($volslist{'ext'}{$key}{$vol}{'path'}, $key, 0)}; # Ссылки на wordnet-ы
	    };
	};
    };

    unless (exists $volslist{'nl'}) {logmsg("No Natural language volumes found!", 'sys'); return};
    foreach $lngcode (sort keys %{$volslist{'nl'}}) {
	$procname = getprocname($lngcode);
	foreach $name (sort keys %{$volslist{'nl'}{$lngcode}}) {
	    readnlvol ($volslist{'nl'}{$lngcode}{$name}{'path'}, $lngcode, $procname);
	};
    };
}

sub processdir { # Поиск csv файлов с рекурсивным проходом каталогов. Требует путь к исходному каталогу
    my ($inpath) = @_;
    my ($name, $path, $lngcode, $key);
    local (*ROOT);

    opendir ROOT, $inpath; # Чтение каталога
    my @lst = readdir ROOT;
    closedir ROOT;

    foreach $name (sort @lst) # Просмотр вложенных каталогов и файлов
    {
	if ( no_upwards($name) and $outpath ne catfile ($inpath, $name)) { # Исключим каталог вывода (требует на входе полный путь, т.е. при первом вызове processdir аргумент получается с getcwd)
	    $path = catfile ($inpath, $name);
	
	    if ( -f $path ) {
		$path = decode($sysencoding, $path);
		$name = decode($sysencoding, $name);
		# Тут желательна проверка, годится ли файл
		if ($name =~ m/^dict\-.*\.csv$/i or $name =~ m/^links\-.*\.csv$/i ) { # Отбираются файлы dict* и links*.csv
		    if ($name eq 'dict-unl.csv') {$volslist{'unl'}{'uw'}{$name}{'path'} = $path} # Главный том UW
		    elsif ($name =~ m/^links\-unl.*\.csv$/) {$volslist{'unl'}{'links'}{$name}{'path'} = $path} # Том связей между UW
		    elsif ($name =~ m/^links\-ext\-(.*)\.csv$/) {
			$key = lc($1); # краткое имя ресурса (wn21, wn30, sumo ...)
			$volslist{'ext'}{$key}{$name}{'path'} = $path} # Том связей с внешними ресурсами
		    elsif ($name =~ m/^dict\-nl\-(...)\.csv$/i or $name =~ m/^dict\-index\-(.*)\.csv$/i) { # Тома естественных языков
			$lngcode = lc($1); # Код языка должен быть в имени тома (Добавить суффикс для диалектов?)
			unless (exists $volslist{$name} and $volslist{$name}) { # Исключение двойников (Может быть потом организовать слияние разных томов)
			    $volslist{'nl'}{$lngcode}{$name}{'path'} = $path;
			} else {
			    logmsg("Alternatve $name is found: $path.\n	Using: $volslist{$name}{'path'}.", 'sys');
			};
		    };
		};
	    }; 
	    if ( -d $path ) { # Если каталог, то добавить в список рекурсии
		processdir($path); # Рекурсия
	    }
	}
    }
} 

sub readlnkvol ($$) { # Чтение списка сем. связей между UW
    my ($file, $nocheck) = @_;
    my ($a, $rel, $b);

    unless(%pivot) {logmsg("Unable to import links between UWs without reading the list of the UWs first", 'sys'); die};
    logmsg("Reading UNL inter-UW links ($file).", 'status');
    open (SRC, "< $file") or die "Unable to read \"$file\".\n";
    while (<SRC>) {
	s/$n$//;
	chomp;
	$_ = decode("utf-8", $_);
	($a, $rel, $b, $marks) = split(/	/, $_);
	if ($a and $rel and $b) {
	    $a =~ s/^\s+//; $a =~ s/\s+$//;
	    $rel =~ s/^\s+//; $rel =~ s/\s+$//;
	    $b =~ s/^\s+//; $b =~ s/\s+$//;
	    if ($marks) {$marks =~ s/^\s+//; $marks =~ s/\s+$//};
	
	    # Восстановление ссылок со старыми UW
	    if (not exists $pivot{$a} and exists $uwlist{'history'}{$a}) {$a = $uwlist{'history'}{$a}; logmsg("Updated link with an old UW \"$a\"", 'data')};
	    if (not exists $pivot{$b} and exists $uwlist{'history'}{$b}) {$b = $uwlist{'history'}{$b}; logmsg("Updated link with an old UW \"$b\"", 'data')};

	    if (exists $pivot{$a} or $nocheck) { # nocheck - позволяет добавлять список связей до добавления самих слов
	    if (exists $pivot{$b} or $nocheck) {
		$uwlinks{$rel}{$a}{$b} = $marks; # Запомним список с пометками
		$invuwlinks{$rel}{$b}{$a} = $marks; # Запомним список с пометками
	    } else {logmsg("UW $b does not exist in the master UW volume. Bad link   $a --$rel--> $b.", 'data')};
	    } else {logmsg("UW $a does not exist in the master UW volume. Bad link   $a --$rel--> $b.", 'data')};
	} else {
	    logmsg("Malformed link \"$_\"", 'data');
	};
    };

    close SRC;
}

sub readontolnkvol ($$$) { # Чтение списка сем. связей между UW и онтологиями
    my ($file, $key, $nocheck) = @_;
    my ($uw, $rel, $t, $path);

    unless(%pivot) {logmsg("Unable to import links between UWs and ".uc($key)." without reading the list of the UWs first", 'sys'); die};
    logmsg("Reading UNL <-> ".uc($key)." links ($file).", 'status');
    open (SRC, "< $file") or die "Unable to read \"$file\".\n";
    while (<SRC>) {
	s/$n$//;
	chomp;
	$_ = decode("utf-8", $_);
	unless (m/^#/) {
	($uw, $rel, $t, $path) = split(/	/, $_);
	if ($uw and $rel and $t) {
	    $uw =~ s/^\s+//; $uw =~ s/\s+$//;
	    $rel =~ s/^\s+//; $rel =~ s/\s+$//;
	    $t =~ s/^\s+//; $t =~ s/\s+$//;
	
	    # Восстановление ссылок со старыми UW
	    if (not exists $pivot{$uw} and exists $uwlist{'history'}{$uw}) {$uw = $uwlist{'history'}{$uw}; logmsg("Updated link with an old UW \"$uw\"", 'data')};

	    if (exists $pivot{$uw} or $nocheck) { # nocheck - позволяет добавлять список связей до добавления самих слов
		$pivot{$uw}{'unl'}{$key}{$rel}{$t} = $path; # Запоминается список связей-триплетов и необязательная строчка пути в онтологии
	    } else {logmsg("UW $uw does not exist in the master UW volume. Bad link   $uw --$rel--> $t.", 'data')};
	} else {
	    logmsg("Malformed link \"$_\"", 'data');
	};
	};
    };
    close SRC;
}

sub readwnlnkvol ($$$) { # Чтение списка сем. связей между UW и Wordnet
    my ($file, $key, $nocheck) = @_;
    my ($uw, $rel, $t, $path);

    unless(%pivot) {logmsg("Unable to import links between UWs and Wordnet without reading the list of the UWs first", 'sys'); die};
    logmsg("Reading UNL <-> ".uc($key)." links ($file).", 'status');
    open (SRC, "< $file") or die "Unable to read \"$file\".\n";
    while (<SRC>) {
	s/$n$//;
	chomp;
	$_ = decode("utf-8", $_);
	unless (m/^#/) {
	($uw, $rel, $pos, $index, $offset) = split(/	/, $_);
	if ($uw and $rel and $pos and $index and defined $offset) {
	    $uw =~ s/^\s+//; $uw =~ s/\s+$//;
	    $rel =~ s/^\s+//; $rel =~ s/\s+$//;
	    $pos =~ s/^\s+//; $pos =~ s/\s+$//;
	    $index =~ s/^\s+//; $pos =~ s/\s+$//;
	    $offset =~ s/^\s+//; $offset =~ s/\s+$//;
	
	    # Восстановление ссылок со старыми UW
	    if (not exists $pivot{$uw} and exists $uwlist{'history'}{$uw}) {$uw = $uwlist{'history'}{$uw}; logmsg("Updated link with an old UW \"$uw\"", 'data')};

	    if (exists $pivot{$uw} or $nocheck) { # nocheck - позволяет добавлять список связей до добавления самих слов
		$pivot{$uw}{'unl'}{$key}{$pos}{$offset}{'index'} = $index;
		$pivot{$uw}{'unl'}{$key}{$pos}{$offset}{'rel'} = $rel;
	    } else {logmsg("UW $uw does not exist in the master UW volume. Bad link   $uw --$rel--> $t.", 'data')};
	} else {
	    logmsg("Malformed link \"$_\"", 'data');
	};
	};
    };
    close SRC;
}

sub readunlvol ($) { # Чтение UNL-словаря-посредника
    my ($file) = @_;
    my ($uw, $etapuw, $history, $comm, $ex, $status, $author, $freq, $srclang, $dummy, $olduw);#, $olduw);

    logmsg("Reading UNL dictionary ($file)...", 'status');
    open (SRC, "< $file") or die "Unable to read \"$file\".\n";

    while (<SRC>) {
	s/$n$//;
	s/;$//;
	chomp;
	$_ = decode("utf-8", $_);
	($uw, $etapuw, $history, $comm, $ex, $dummy, $status, $author, $freq, $srclang) = split(/	/, $_);

	if ($uw and $uw =~ m/^\[(.*)\]$/) {$uw = fixuw($1)};
	if ($etapuw and $etapuw =~ m/^\{(.*)\}$/) {$etapuw = $1};
	if ($history and $history =~ m/^\"(.*)\"$/) {$history = $1};
	if ($comm and $comm =~ m/^\"(.*)\"$/) {$comm = $1};
	    $comm =~ s/^[\s\"]+//; $comm =~ s/[\s\"]+$//;
	if ($ex and $ex =~ m/^\"(.*)\"$/) {$ex = $1};
	    $ex =~ s/^[\s\"]+//; $ex =~ s/[\s\"]+$//;
	if ($srclang and $srclang =~ m/^\"(.*)\"$/) {$srclang = $1};
	if ($freq and $freq =~ m/^FREQ\=(\d+)$/) {$freq = $1};

	if ($uw and $uw =~ m/^[a-z0-9\.\'\_\-#&%\|]+(\([a-z0-9\.\'\_\-#&%\|\<\>\(\)\,]+\))$/i) { # Отсев мусора на месте UW
	    $pivot{$uw}{'unl'}{'etapuw'} = $etapuw;
	    if ($history) { @{$pivot{$uw}{'unl'}{'history'}} = split($olduwdelim, $history) }; # Сохраняем упорядоченный список старых форм UW
	    foreach $olduw (@{$pivot{$uw}{'unl'}{'history'}}) {$uwlist{'history'}{$olduw} = $uw}; # Список старых форм в uwlist для блокирования повторного использования
	    $pivot{$uw}{'unl'}{'comm'} = $comm;
	    $pivot{$uw}{'unl'}{'ex'} = $ex;
	    $pivot{$uw}{'unl'}{'status'} = $status;
#	    parsestatus ($status, \%{$pivot{$uw}{'unl'}{'status'}}, \${$pivot{$uw}{'unl'}{'rating'}}); # разбор строки статуса связи
	    $pivot{$uw}{'unl'}{'author'} = $author;
	    $pivot{$uw}{'unl'}{'freq'} = $freq;
	    $pivot{$uw}{'unl'}{'srclang'} = $srclang;
	} elsif (defined $uw) { logmsg("Ignoring bad UW: $uw", 'data') };
    };

    close SRC;
}


sub readnlvol ($$$) { # Чтение словаря естественного языка
    my ($file, $lngcode, $procname) = @_;
    my ($w, $proc, $uw, $comm, $ex, $pos, $status);

    logmsg("Reading $lngcode dictionary ($file)...", 'status');
    open (SRC, "< $file") or die "Unable to read \"$file\".\n";
    while (<SRC>) {
	s/$n$//;
	s/;$//;
	chomp;
	$_ = decode("utf-8", $_);
	($w, $proc, $uw, $comm, $ex, $pos, $status) = split(/	/, $_);
	if ($w and $w =~ m/^\[(.*)\]$/) {$w = $1}; unless (defined $w) {$w = ''};
	if ($proc and $proc =~ m/^\{(.*)\}$/) {$proc = $1}; unless (defined $proc) {$proc = ''};
	if ($uw and $uw =~ m/^\"(.*)\"$/) {$uw = fixuw($1)};
	if ($comm and $comm =~ m/^\"+(.*)\"+$/) {$comm = $1}; unless (defined $comm) {$comm = ''};
	    $comm =~ s/^[\s\"]+//; $comm =~ s/[\s\"]+$//;
	    if ($comm =~ /^(...)\:/ and $1 ne $lngcode) {$comm = ''}; # Защита от иноязычных определений
	    #$comm =~ s/^$lngcode\://; # Здесь считается, что код языка совпадает с языком словаря.
	if ($ex and $ex =~ m/^\"+(.*)\"+$/) {$ex = $1}; unless (defined $ex) {$ex = ''};
	    $ex =~ s/^[\s\"]+//; $ex =~ s/[\s\"]+$//;
	    if ($ex =~ /^(...)\:/ and $1 ne $lngcode) {$ex = ''}; # Защита от иноязычных определений
	    #$ex =~ s/^$lngcode\://; # Здесь считается, что код языка совпадает с языком словаря.
	    if (exists $cyrilliclng{$lngcode} and exists $pivot{$uw} and exists $pivot{$uw}{'unl'}{'srclang'} and exists $cyrilliclng{$pivot{$uw}{'unl'}{'srclang'}} and not $ex =~ m/[а-я]/) {$ex = ''};
	if ($status and $status =~ m/^\"(.*)\"$/) {$status = $1}; unless ($status) {$status = 'unknown'};
	if ($pos and $pos =~ m/^[\{\"](.*)[\}\"]$/) {$pos = $1; $pos = normpos($pos)}; unless (defined $pos) {$pos = ''};

	if (defined $w and defined $uw and $uw =~ m/^[a-z0-9\.\'\_\-#&%\|]+(\([a-z0-9\.\'\_\-#&%\|\<\>\(\)\,]+\))$/i) { # Отсев мусора на месте UW

	
	    if (exists $pivot{$uw}) { # только те УВ, которые описаны в unlvolume
		# Если такой перевод уже есть, то взять вариант с одинаковым глоссом и частью речи при более длинной строке proc
		if (not exists $pivot{$uw}{'trans'}{$lngcode}{$w}{$proc} or ($pivot{$uw}{'trans'}{$lngcode}{$w}{$proc}{'pos'} eq $pos and $pivot{$uw}{'trans'}{$lngcode}{$w}{$proc}{'comm'} eq $comm)) {
		    $pivot{$uw}{'trans'}{$lngcode}{$w}{$proc}{'pos'} = $pos;
		    parsestatus ($status, \%{$pivot{$uw}{'trans'}{$lngcode}{$w}{$proc}{'status'}}, \${$pivot{$uw}{'trans'}{$lngcode}{$w}{$proc}{'rating'}}); # разбор строки статуса связи
		    $pivot{$uw}{'trans'}{$lngcode}{$w}{$proc}{'comm'} = $comm;
		    $pivot{$uw}{'trans'}{$lngcode}{$w}{$proc}{'ex'} = $ex;
		} else {logmsg("repeating trans: $lngcode	$w	$uw", 'data')};
	    };
	    






	    #if ($proc and not $pos) {print "$lngcode	$w	$uw	$proc\n"};
	    undef %feats;
	    if ($proc) {
		getnlwfeat($lngcode, $pos, $procname, $proc, \%feats);
	    } else {
		unless ($pos) {$pos = uwdetectpos($uw)};
		if ($lngcode eq 'rus' and $pos and $pos eq 'n' and not exists $feats{'animacity'} and uwdetectanim($uw)) {$feats{'animacity'}{'anim'} = ''};
	    };
	
	
	    # Подготовка ID вокабулы
	    ($wns = $w) =~ s/ /_/g;
	    $vocable = "$lngcode.$wns";
	    if ($pos) { $vocable .= ".$pos"}; # Если потребуется различать омонимы внутри 1 части речи, то можно усложнить
	    if ($feats{'animacity'}) { $vocable .= ".".join(',', sort keys %{$feats{'animacity'}}) };
	    #if ($feats{'gender'}) { $vocable .= ".".join(',', sort keys %{$feats{'gender'}}) };


	    # Подготовка ID лекси
	    unless (exists $cnt{$w}{$proc}) { # Выводить еще раз ту же лекc. единицу не надо, но нужно создать связь
		$cnt{$w}{$proc} = 1; # Запомним, что слово (lexie) с таким набором характеристик уже есть
		if (not exists $cnt{$w}{'cnt'}) {$cnt{$w}{'cnt'} = 1} else {$cnt{$w}{'cnt'}++}; # Присвоение номера текущей лекси (содержимому строки CSV-таблицы)
	    };
	    $lexie = "$dictname.lexie.$lngcode.$wns.$cnt{$w}{'cnt'}";


	    # Все ID определены
	    if ($vocable and  $lexie) {
		#if ($lex{$lngcode}{$vocable}{'lemma'} and $lex{$lngcode}{$vocable}{'lemma'} ne $w) {print "WARNING Lemma $w is different from {$lex{$lngcode}{$vocable}{'lemma'}\n"} else {$lex{$lngcode}{$vocable}{'lemma'} = $w}; # Может сработать если изменится способ формирования вокабул
		$lex{$lngcode}{$vocable}{'lemma'} = $w;
		$lex{$lngcode}{$vocable}{'feat'}{'pos'}{$pos} = ''; # Берется из специального поля, которое олжно быть заполнено
		#getnlwfeat($lngcode, $pos, $procname, $proc, \%{$lex{$lngcode}{$vocable}{'feat'}}); # Сбор свойств "лекси", которые статичны для слова
		foreach $feat (keys %feats) {$lex{$lngcode}{$vocable}{'feat'}{$feat} = $feats{$feat}};
		$lex{$lngcode}{$vocable}{'lex'}{$lexie}{'procname'} = $procname;
		$lex{$lngcode}{$vocable}{'lex'}{$lexie}{'proc'} = $proc;
		$lex{$lngcode}{$vocable}{'lex'}{$lexie}{'uw'}{$uw}{'stat'} = $status;
	    };

	    $pivot{$uw}{'lexies'}{$lngcode}{$lexie} = $vocable;
#	    if ($pivot{$uw}{'comment'}{$lngcode} and $pivot{$uw}{'comment'}{$lngcode} ne $comm) {print "Differing comments for $uw: $pivot{$uw}{'comment'}{$lngcode}   |   $comm\n"};# else {$pivot{$uw}{'comment'}{$lngcode} = $comm}; # Может быть только 1 комментарий к UW для 1 языка
#	    if ($pivot{$uw}{'example'}{$lngcode} and $pivot{$uw}{'example'}{$lngcode} ne $ex) {print "Differing examples for $uw: $pivot{$uw}{'example'}{$lngcode}   |   $ex\n"};# else {$pivot{$uw}{'example'}{$lngcode} = $ex}; # Может быть только 1 комментарий к UW для 1 языка


	} elsif (defined $w and defined $uw) {logmsg("Ignoring bad UW: $uw", 'data')};
    };
    close SRC;
}


sub makeolduwlist ($) {
    my ($uw) = @_;
    my $olduws = '';

#    $uwlist{'updated'}{$olduw} = $uw; # В дальнейшем этот список учитывается при выводе таблиц общего словаря
    if (exists $pivot{$uw}{'unl'}{'history'}) {
#    print "$uw	".join($olduwdelim, @{$pivot{$uw}{'unl'}{'history'}})."\n";
    $olduws = join($olduwdelim, @{$pivot{$uw}{'unl'}{'history'}})}; # список новых переименований uwlist
    return $olduws;
};





#######################################################################################
# Вставка ссылок на лингвистический процессор при их отсутствии 
#######################################################################################

sub normpos ($) { # Нормализуем метку части речи
    my ($pos)=@_;
    $pos = lc($pos);
    $pos =~ s/\.$//;
    if ($pos eq 'adj') {return 'a'};
    if ($pos eq 's') {return 'n'};
    if ($pos eq 'prep') {return 'pr'};
    return $pos;
};

sub getpos ($$$) { # Разные способы определения части речи
    my ($uw, $w, $lngcode) = @_;
    my $wproc = ''; 
    my $pos = '';
    
    # Просто берем часть речи уже имеющегося слова
    if (exists $pivot{$uw}) { # and exists $pivot{$uw}{'trans'}{$lngcode}{$w}) {
	foreach $wproc (keys %{$pivot{$uw}{'trans'}{$lngcode}{$w}}) {
	    $pos = $pivot{$uw}{'trans'}{$lngcode}{$w}{$wproc}{'pos'}; # Пока нет лучшего
	};
    };
    if (not $pos) {$pos = uwdetectpos ($uw)};
    return $pos;
}


sub getsumoterms ($$) { # Получить список классов SUMO
    my ($s, $terms) = @_;
    my ($rel, $cl, $ps, $t);
    my @p;
    
    foreach $rel (keys %{$s}) {
	foreach $cl (keys %{${$s}{$rel}}) { # перебор классификаторов
	    @p = split('/', ${$s}{$rel}{$cl}); # Делим строку пути (если есть)
	    foreach $ps (@p) { # альтернативные пути
		foreach $t (split(/[\@\<\>]/, $ps)) { # отдельные термы в пути
		    ${$terms}{$t} = $ps; # Если это не обязательный entity, то в список вместе с путем
		};
	    };
	};
    };
}


sub chooselexbysemtags ($$$$$) { # Выбор лексемы по имеющимся сем. признакам
    my ($lngcode, $sw, $candlex, $uw, $pos) = @_;
    my $lex;
my %semtrans;
#$semtrans{'АБСТРАКТ'}{'ABSTRACT'} = '';
$semtrans{'ПРЕДМЕТ'}{'OBJECT'} = '';
$semtrans{'ДЕЙСТВИЕ'}{'INTENTIONALPROCESS'} = '';
$semtrans{'СОСТОЯНИЕ'}{'ATTRIBUTE'} = '';
$semtrans{'СТАТИВ'}{'ATTRIBUTE'} = '';
#$semtrans{'СТАТИВ'}{'PROCESS'} = '';
#$semtrans{'ПРОЦЕСС'}{'PROCESS'} = '';
#$semtrans{'ФАКТ'}{'PROCESS'} = '';
$semtrans{'ПРОСТРАНСТВО'}{'REGION'} = '';
$semtrans{'ЧЕЛОВЕК'}{'HUMAN'} = '';
$semtrans{'ЖЕНЩИНА'}{'WOMAN'} = '';
$semtrans{'МУЖЧИНА'}{'MAN'} = '';
$semtrans{'ЛИЦО'}{'AGENT'} = '';
$semtrans{'ОБРАЩ'}{'AGENT'} = '';
$semtrans{'УЧРЕЖДЕНИЕ'}{'ORGANIZATION'} = '';
$semtrans{'ВЕЩЕСТВО'}{'SUBSTANCE'} = '';
#$semtrans{'ВЕЩЕСТВО'}{'OBJECT'} = '';
$semtrans{'ЧАСТЬ'}{'PART'} = '';
$semtrans{'ПАРАМ'}{'ATTRIBUTE'} = '';
$semtrans{'ПАРАМЕТР'}{'ATTRIBUTE'} = '';
$semtrans{'ЧУВСТВО'}{'EMOTIONALSTATE'} = '';
#$semtrans{'СОСТОЯНИЕ'}{'SUBJECTIVEASSESSMENTATTRIBUTE'} = '';
$semtrans{'СОВОКУПНОСТЬ'}{'COLLECTION'} = '';
$semtrans{'СОВОК'}{'COLLECTION'} = '';
$semtrans{'ДВИЖ'}{'MOTION'} = '';
$semtrans{'ВЕЛИЧИНА'}{'QUANTITY'} = '';
$semtrans{'ВМЕСТИЛИЩЕ'}{'CONTAINER'} = '';
$semtrans{'ДОЛЖНОСТЬ'}{'SOCIALROLE'} = '';
$semtrans{'ПРОФ'}{'SOCIALROLE'} = '';
$semtrans{'ИНФОРМАЦИЯ'}{'CONTENTBEARINGPHYSICAL'} = '';
$semtrans{'ИЗМЕН'}{'INTERNALCHANGE'} = '';
$semtrans{'ОРГАН'}{'BODYPART'} = '';
$semtrans{'АНАТ'}{'ANATOMICALSTRUCTURE'} = '';
#$semtrans{'БЕНЕФ'}{''};


    # Определить набор классов по ссылке на SUMO
    my %onto;
    getsumoterms(\%{$pivot{$uw}{'unl'}{'sumo'}}, \%onto);

    
    # Определить уникальные дескрипторы лексемы
    my %des; my %uniqdes;
    my ($d, $t);
    foreach $lex (@{$candlex}) {
	foreach $d (split(',', $syntags{$lngcode}{$sw}{$lex}{'des'})) {$d =~ s/^\s*\'//; $d =~ s/\'\s*$//; push(@{$des{$d}}, $lex)}; # Сбор всех дескрипторов
	foreach $d (split(',', $syntags{$lngcode}{$sw}{$lex}{'synt'})) {push(@{$des{$d}}, $lex)}; # Сбор всех дескрипторов
    };

    foreach $d (keys %des) {
	if ($#{$des{$d}} eq 0) {$uniqdes{"${$des{$d}}[0]"}{$d} = ''}; # Сбор списка дескрипторов, которые есть только у одной лексемы из числа омонимов $sw
    };

    #  Сравниваем
    my %cmp;
    foreach $lex (@{$candlex}) {
	foreach $d (keys %{$uniqdes{$lex}}) { # Если у этого омонима есть уникальные дескрипторы
		if (exists $semtrans{$d}) { # И они соответствуют каким-то классам онтологии
		    foreach $t (keys %{$semtrans{$d}}) { # Все предполагаемые термы онтологии
			if (exists $onto{$t}) {$cmp{'yes'}{$lex}++} else {$cmp{'no'}{$lex}++}; # Подчет очков за и против
		    };
		};
	};
	$cmp{'all'}{$lex} = 0;
    };

    foreach $lex (keys %{$cmp{'all'}}) {
	if (exists $cmp{'no'}{$lex}) {delete $cmp{'all'}{$lex}}; # Исключить лексемы с противоречащими дескрипторами
    };
    
    my $best = '';
    foreach $lex (keys %{$cmp{'yes'}}) { # Если есть лексемы с совпадающими с онтологией дескрипторами
	if (not exists $cmp{'yes'}{$best} or ($cmp{'yes'}{$lex} > $cmp{'yes'}{$best}) )  {$best = $lex}; # Отбор лексемы с наибольшим числом совпадающих дескрипторов
    };
    if ($best) {
	$stat{'proclinkmatched'}++; 
	return $best;
    };
    return '';

# Отключено из-за большого процента ошибок
#    } elsif (hashknum(\%{$cmp{'all'}}) eq 1) { # Если осталась 1 лексема без противоречащих дескрипторов
#	@_ = join("", keys %{$cmp{'all'}});
#	$lex = $_[0];
#	if ($lex) {
#	    logmsg("$lex	$syntags{$lngcode}{$sw}{$lex}{'comm'}	$uw	$pivot{$uw}{'unl'}{'comm'}	$pivot{$uw}{'unl'}{'sumo'}	class matching (by exclusion)", 'data');
#	    $stat{'proclinkonlypossible'}++; 
#	    #return $lex;
#	    return '';
#	};
};


sub chooselexbytrans ($$$$$) { # Выбор лексемы по дежурному переводу (он может совпадать c UW только у одной лексемы)
    my ($lngcode, $sw, $candlex, $uw, $pos) = @_;
    my ($lex, $hw, $t);
    my %tr; my %uniqtr;

    foreach $lex (@{$candlex}) {
	foreach $t (keys %{$syntags{$lngcode}{$sw}{$lex}{'trans'}}) {push(@{$tr{$t}}, $lex)}; # Сбор всех переводов
    };
    foreach $t (keys %tr) {
	if ($#{$tr{$t}} eq 0) {$uniqtr{"${$tr{$t}}[0]"}{$t} = ''}; # Сбор списка переводов, которые есть только у одной лексемы из числа омонимов $sw
    };

    ($hw = lc($uw)) =~ s/\(.*//;
    foreach $lex (@{$candlex}) {
	if (exists $uniqtr{$lex}{$hw}) { # Если 
	    #logmsg("trans $lex => $uw	$syntags{$lngcode}{$sw}{$lex}{'comm'}", 'data');
	    #logmsg("$lex	$syntags{$lngcode}{$sw}{$lex}{'comm'}	$uw	$pivot{$uw}{'unl'}{'comm'}	$pivot{$uw}{'unl'}{'sumo'}	by trans", 'data');
	    $stat{'proclinktrans'}++; 
	    return $lex;
	};
    };

}

sub getproclink ($$$$) {
    my ($sw, $lngcode, $pos, $uw) = @_;
    my (@candlex, $lex);

    $sw = lc($sw);
    $sw =~ s/\_/ /g;
    if (exists $syntags{$lngcode}{$sw}) { # Если есть ссылка на синт. данные (набор лексем словаря процессора)

	    foreach $lex (sort keys %{$syntags{$lngcode}{$sw}}) {
		if ($pos eq $syntags{$lngcode}{$sw}{$lex}{'pos'}) {push(@candlex, $lex)}; # Сбор списка лексем с совпадающей меткой части речи
	    };

	    if ($#candlex eq 0) { # Если есть только 1 лексема ЭТАП (или др. системы) с такой частью речи
		$lex= $candlex[0];
	    } elsif ($#candlex > 0) {
		$lex = chooselexbytrans($lngcode, $sw, \@candlex, $uw, $pos);
		unless ($lex) {$lex = chooselexbysemtags($lngcode, $sw, \@candlex, $uw, $pos)};
	    };
    };
    if ($lex and exists $syntags{$lngcode}{$sw}{$lex}) {
	if (getprocname($lngcode) eq 'ETAP') {
	    return $lex.":".$syntags{$lngcode}{$sw}{$lex}{'synt'};
	} else {
	    return $syntags{$lngcode}{$sw}{$lex}{'synt'};
	};
    } else {return ''};
}

sub getprocname ($) {
    my ($lngcode) = @_;
    if (exists $processors{$lngcode}) {return $processors{$lngcode}} else {return ''};
}


####################################################
# Обработка строк статуса связей между словами и UW
####################################################

sub parsestatus ($$$) { # разбор строки статуса связи
    my ($s, $h, $r) = @_;
    $rating = ''; my $f;

    if ($s =~ m/^([\d\*]*),(.*)/) {$rating = $1; $s = $2};
    foreach $f (split("\-", $s)) {${$h}{$f} = ''};
    if (exists ${$h}{"auto"} and exists ${$h}{"manual"}) {delete ${$h}{"auto"}};
    if (exists ${$h}{"monosemic"} and exists ${$h}{"polysemic"}) {delete ${$h}{"monosemic"}};
    ${$r} = $rating;
}


#######################################################################
# Начало
######################################################################

setencoding;
if ( not $#ARGV + 1) { 
    logmsg("This script finds all volumes of the U++ UNL dictionary, reads them and applies different transformations (corrections of UW-NL word links, renaming of UWs...)\nInstructions are read from special csv tables\n<path to UNL dictionary volumes>", 'status');
} else { 
    if (not $ARGV[0]) {logmsg("No path to TGT files given", 'sys'); die};

    # Если дан относительный путь, добавить его к текущему каталогу
    unless ($ARGV[0] =~ m/^\//) {
	$spath = catdir (getcwd(), $ARGV[0]);
    } else {
	$spath = $ARGV[0];
    };

    # Обработка файлов словаря
    logmsg("Processing directory \"".decode($sysencoding, $spath)."\"\n", 'status');
    processdir($spath); # строит список файлов словаря %volslist
    readvols; # Запускает чтение файлов словаря




    print "Writing UNL XDXF dictionary...\n";
    makepivotxdxf;

    print "Writing NL XDXF dictionaries...\n";
    makenlxdxf;

    print "Finished.\n"; 

};

