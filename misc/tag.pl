#!/usr/bin/perl

# This is needed, I really didn't want to have to rewrite all the ID3 functions :)
use MPEG::MP3Info;
system('clear');
print "\nPath to MP3: ";
chop($file = <>);
open(MP3, "$file") or die "Couldn't open \'$file\', $!\n";
my $tag = get_mp3tag($file);
print "\nTitle of the song: ";
chop($tag->{TITLE}=<>);
print "\nArtist: ";
chop($tag->{ARTIST}=<>);
print "\nAlbum name: ";
chop($tag->{ALBUM}=<>);
print "\nYear: ";
chop($tag->{YEAR}=<>);
print "\nComment: ";
chop($tag->{COMMENT}=<>);
print "\nGenre (see genres.txt for a list by index): ";
chop($tag->{GENRE}=<>);
set_mp3tag($file, $tag) or die "Couldn't write TAG, $!\n";

