# ampd.pm - A programmer's interface to ampd.
# This module was mostly written for the switch to GUI.
# Send all comments, questions, bugs, etc. to ampd@mail.com

use MPEG::MP3Info;
use genres;

package ampd;

# the ampd (main) package.
# global functions are placed here. (playsong, readID3, die_nice)


# playsong usage: playsong(SONG, \INIT_SUB, \WHILE_PLAYING_SUB, \END_SUB)
# The INIT_SUB will be passed all the ID3 information of the mp3 as an array
# (see readID3)
sub bynum { $a <=> $b }

sub playsong{
	my($song, $init, $while_playing, $end) = @_;
	die_nice("No song specified\n") if !$song;
	my (@ID3info, $info);
	@ID3info = readID3($song);
	$info = MPEG::MP3Info::get_mp3info($song);
	$init->(@ID3info, $info->{MM}, $info->{SS}) if $init;
	undef $return;
	if($pid = fork)
	{
		$done = 0;
		$SIG{CHLD} = sub{$done=1};
		$then = time;	
		while($done == 0)
		{
			$now = time;
			$seconds = int($now - $then); 	
			$return = $while_playing->($seconds) if $while_playing;
			if($return == 1)
			{
				kill 9, $pid;
				undef $return;
			}
		}
		wait;
	}	
	else { $song=~ s/ /\\ /g; exec("mpg123 $song") }
	$seconds = 0;
	&$end if $end;
}

# readID3 usage: ($tag, $title, $artist, $album, $year, $comment, $genre_num) =
# readID3(FILE)

sub readID3{
	# Thanks to www.id3.org for the great info.
	my ($file)=@_;
	open(MP3,$file) || die_nice("error opening '$file': $!\n");
	seek(MP3,-128,2);
	read(MP3,$info,128);
	# returns (tag,title,artist,album,year,comment,genre_number)
	my ($tag,$title,$artist,$album,$year,$comment,$genre_number) = unpack('a3a30a30a30a4a30C1',$info);
	if ($tag eq 'TAG'){
		$title=~ s/(^\s*|\s*$)//g;
		$album=~ s/(^\s*|\s*$)//g;
		$artist=~ s/(^\s*|\s*$)//g;
		$comment=~s/(~\s*|\s*$)//g;
	}else{
		$title = 'No Title';
		$artist = 'No Artist';
		$album = 'No Album';
		$comment = 'No Comment';
	}
	$title ||= 'No Title';
	$artist||= 'No Artist' ;
	$album ||= 'No Album';
	$comment ||= 'No Comment';
	$genre = $genre_number == 255 ? 'No Genre' : $genres->[$genre_number];
	return ($tag, $title, $artist, $album, $year, $comment, $genre_number);
	
	
}

# die_nice usage: die_nice(err_msg)

sub die_nice{
	my $err = shift;
	my $caller = (caller(0))[3];
	$caller =~ s!.*::!!g;
	print "\n$caller: $err\n";
	exit;
}

# playlist package. here you can open/edit/save/do anything with a playlist


package Playlist;

# new constructor, usage: $playlist = new Playlist OR $playlist =
# Playlist->new;

sub new{
	
	my ($package) = @_;
	my $self = {};
	$self->{_type} = 'PLAYLIST';
	bless $self, $package;
	return $self;

}

# open usage: $playlist->open(PLAYLIST)
# sets up a playlist object.

sub open{

	my ($self, $file) = @_;
	my ($block, @ALIAS, $order, $song, $times);
	$file = ref($file) eq 'HASH' ? $file->{file} : $file;
	
	open(PLAYLIST, $file) or die "Could not open \'$file\' :
$!\n";
	 while (<PLAYLIST>){
        next if /^#/;
		if (/ALIAS\s?\t?\{/ || $block == 1){
            $block = 1;
            $block = 0 if /^\s?\t?\}/;
            $ALIAS[$1]=$2 if /^(\d)\s*\t*=\s*\t*(.*)$/;
        }
        $order++;
		($song, $times) = split /\;/;
		$song =~ s/\$(\d+)/$ALIAS[$1]/eg;
		next if !$song || !$times ;
        for( 1 .. $times ){
			$order++ if $_ > 1;
			$self->{$order} = $song;
			$self->{total}++;
		}
	}
}


# play usage: $playlist->play; OR $playlist->play(	song => SONG, 
# 													init => INIT_SUB, 
#													playing => PLAYING_SUB,
#													end => END_SUB);

sub play{

	my ($self, %args) = @_;
	my ($init, $playing, $end);
	$which = $args{song} || $args{SONG};
	$init = $args{init} || $args{INIT};
	$playing = $args{playing} || $args{PLAYING};
	$end = $args{end} || $args{END};	
	die "Not a Playlist reference: \'$self->{_type}\'" if $self->{_type} ne 'PLAYLIST';
	if ($which)
	{	
		&ampd::playsong($self->{$which},$init, $playing, $end);	
	}
	else{
		for (1..$self->{total})
		{
			&ampd::playsong($self->{$_},$init, $playing, $end);
		}
	}
}		

# catalog package

package Catalog;

# new constructor, usage: $catalog = new Catalog OR $catalog = Catalog->new

sub new{
	
	my ($package) = @_;
	my $self = {};
	$self->{_type} = 'CATALOG';
	bless $self, $package;
	return $self;

}

# open usage: $catalog->open (This will default to ~/.ampd_catalog) OR
# $catalog->open(PATH_TO_CATALOG)

sub open{

	my ($self, $file) = @_;
	my ($section);
	$file ||= '~/.ampd_catalog';
	$file =~ s/\~/$ENV{HOME}/eg;
	open(CATALOG,$file) || &ampd::die_nice("error opening catalog: $!\n");
	while(<CATALOG>)
	{
		if (/_SECTION/)
		{
			/_SECTION\s+(.+\w)\s*\{/;
			$section = $1;
			$section =~ s/\n//g;
			$block = 1 if $section;
		}
		if ($block)
		{
			$block = 1;
			$block = 0 if /^\s?\t?\}/;
			$self->{$section}{$1}{label} = $2 if /LABEL\[(.*)\]\s*\=\s*(.*)$/;
			$self->{$section}{$1}{artist} = $2 if /ARTIST\[(.*)\]\s*=\s*(.*)$/;
			$self->{$section}{$1}{file} = $2 if /FILE\[(.*)\]\s*=\s*(.*)$/;		
			$self->{$section}{$1}{album} = $2 if /ALBUM\[(.*)\]\s*=\s*(.*)$/;
		}
	}		
	$self->{_file} = $file;
	close(CATALOG);
}

# total usage: $catalog->total (counts total number of sections)

sub total{
	my ($self) = @_;
	return scalar(keys %{$self}) - 2;
}

sub files{
	my ($self, %args) = @_;
	my $section;
	
	$section = $args{'-section'} || $args{'section'};
	push (@files, $self->{$section}{$_}{file}) for keys %{ $self->{$section} };
	@files;
}
sub sections{
	my ($self) = @_;
	# ugh this is a quick hack, trying to think of a better way to do this?
	delete $self->{_type};
	my $file = delete $self->{_file};
	my @sections = keys %{$self};
	$self->{_type} = 'CATALOG';
	$self->{_file} = $file;
	return @sections;
}


# play usage: $catalog->play(	-section => SECTION,
#								-init => INIT_SUB,
#								-playing => PLAYING_SUB,
#								-end =>	END_SUB)

sub play{
	my ($self, %args) = @_;
	my ($section, $which, $init, $playing, $end);
	
	$section= $args{'-section'} || $args{section} || $args{SECTION};
	$which 	= $args{'-song'} || $args{song} || $args{SONG};
	$init 	= $args{'-init'} || $args{init} || $args{INIT};
	$playing= $args{'-playing'} || $args{playing} || $args{PLAYING};
	$end 	= $args{'-end'} || $args{end} || $args{END};	
	
	bless $init, 'ampd';
	bless $playing, 'ampd';
	bless $end, 'ampd';
	
	&ampd::die_nice("No Section specified!\n") if !$self->{$section};
	&ampd::die_nice("Not a Catalog reference: \'$self->{_type}\'\n") if $self->{_type} ne 'CATALOG';
	if ($which)
	{
		&ampd::playsong($self->{$section}{$which}{file},$init, $playing, $end);
	}else{
		for(1..$self->total)
		{
			&ampd::playsong($self->{$section}{$_}{file},$init, $playing, $end);
		}
	}
}

sub add{

	my ($self, %args) = @_;
	my ($section, $directory, $catalog, $status_obj);
	
	$catalog = $self->{_file};
	$section = $args{'-section'} || $args{section};
	$directory = $args{'-directory'} || $args{'-dir'} || $args{'directory'} ||$args{'dir'};
	$status_obj = $args{'-statusvar'} || $args{'-statvar'} || $args{statusvar} || $args{statvar};
	
			
	&ampd::die_nice("section already exists\n") if $self->{$section};
	chdir($directory);
	chop($pwd = `pwd`);
	opendir(DIR, $directory) || ampd::die_nice("unable to open directory: $!\n");
	$$status_obj = "Creating Section \'$section\'...\n";
	open(CAT, ">>$catalog") || &ampd::die_nice("unable to open catalog: $!\n");
	print CAT "_SECTION $section {\n";
	$id = 0;
	foreach(sort {$a <=> $b} (grep{/\.mp3/i} readdir(DIR)) )
	{
		$id++;
		my @info = &ampd::readID3($_);
		($title, $artist, $album) = @info[1..3];
		if($info[0] ne 'TAG'){ $title = 'No Title'; $artist = 'No Artist'; $album = 'No Album' }
		$$status_obj = "Adding \'$_\'...\n";
		print CAT <<THIS;
			FILE[$id] = $pwd/$_
			LABEL[$id] = $title
			ARTIST[$id] = $artist
			ALBUM[$id] = $album
			
THIS
	}
	print CAT "}\n";
	$self->update;
	$$status_obj = "Done\n";
}

sub update{

	my ($self) = @_;
	my $file = $self->{_file};
	$self = new Catalog;
	$self->open( $file );
}

sub remove{

	my ($self, %args) = @_;
	my ($section, $status_obj);
	
	$section = $args{'-section'} || $args{'section'};
	$status_obj = $args{'-statusvar'} || $args{'-statvar'} || $args{statusvar} || $args{statvar};
	
	my $catalog = $self->{_file};
	$catalog =~ s/\~/$ENV{HOME}/eg;
	open(CAT, $catalog) || &ampd::die_nice("error opening catalog: $!");
	while(<CAT>)
	{
		$block = 1 if /_SECTION\s*$section\s*\{/;
		$$status_obj = 'Deleting..' if $block == 1;
		push(@new_catalog, $_) if !$block;
		undef $block if ($block == 1 && /^\s*\}/);
   	}
	open(CAT, ">$catalog") ||  &ampd::die_nice("error writing to catalog: $!\n");
   	print CAT @new_catalog;
	close(CAT);
	$$status_obj = 'Finished';
}

sub rename{

	my ($self, %args) = @_;
	my ($section, $newname, $catalog);
	
	$section = $args{'-section'} || $args{'section'};
	$newname = $args{'-newname'} || $args{'newname'};

	$catalog = $self->{_file};	
	$catalog =~ s/\~/$ENV{HOME}/eg;
	open(CAT, $catalog) || ampd::die_nice("error opening catalog: $!");
	@renamed = grep { s/$section/$newname/ if /_SECTION/} (<CAT>);
	close CAT;
	open(CAT, ">$catalog");
	print CAT @renamed;
	close CAT;
	$self->update;
}

sub addsong{ 
	
	my ($self, %args) = @_;
	my ($section, $song, $total, $catalog, @current, @info);

	$section = $args{'-section'} || $args{'section'};
	$song = $args{'-song'} || $args{'song'};
	
	$catalog = $self->{_file};
	$catalog =~ s/\~/$ENV{HOME}/eg;

	print "Section => $section\n";
	print 'keys => ', keys %{ $self->{$section} };	
	$total = scalar($self->files(-section => $section)); #scalar(keys %{ $self->{$section} });

	$total++;
	
	print "Total = $total\n";	
	# Insert it here..
	@info = (ampd::readID3($song))[1..3];
	
	$self->{$section}{$total} = { file => $song, label => $info[0],
								artist => $info[1], album => $info[2]
								};
	
	# delete the section, and reprint it w/updated info.

	$self->remove( -section => $section);

	open(CAT, ">>$catalog") || ampd::die_nice("error opening catalog: $!");

	print CAT "_SECTION $section {\n";
	my $id = 0;
	for ( sort {$a <=> $b} (keys %{ $self->{$section} }))
	{
		$id++;
		print CAT <<THIS;
			FILE[$id] = $self->{$section}{$id}{file}
			LABEL[$id] = $self->{$section}{$id}{label}
			ARTIST[$id] = $self->{$section}{$id}{artist}
			ALBUM[$id] = $self->{$section}{$id}{album}
			
THIS
	}
	print CAT "}\n";
	close CAT;
	$self->update;	
}			

1;
