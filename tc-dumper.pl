#!/usr/bin/perl -w
use strict;
use warnings;

use Cwd 'abs_path';
use File::Basename;
use File::Path (); #for creating directories

use Getopt::Long ('GetOptionsFromString', ':config', 'no_auto_abbrev');

use WWW::Mechanize::GZip ();

use JSON;
use Data::Dumper;
$Data::Dumper::Sortkeys=1;
$Data::Dumper::Terse=1;
$Data::Dumper::Quotekeys=0;
#$Data::Dumper::Indent=1;
$|=1;

sub show_help;
sub cd(;$);
sub get_cwd;
sub create_directory($);
sub download_json($);
sub download_image($$);

unless(@ARGV){
	show_help;
}

cd;
my $main_dir = get_cwd;

my %mech_options = 
(
	agent           => '', 		
	autocheck       => 0,  		
	cookie_jar      => undef, 	
	conn_cache		=> undef,
	noproxy         => 1, 
	quiet			=> 1,
	show_progress   => 1,  		
	stack_depth     => 0,  		
	timeout         => 30,
);

my %options = 
(
	user			=> undef,
	api_url 		=> "http://api.tinychat.com/=USER=.json",
	download_images => 0,
	hide_progress 	=> 0,
	overwrite		=> 0,
	save_json		=> 0,
	no_dump			=> 0,
	timeout			=> 0,
	proxy			=> undef,
	loop => 0,
	sleep_interval => 60 * 10,
);

my $arguments = join(' ', @ARGV);
my ($ret, $remain) = GetOptionsFromString($arguments, 
	'u|user|r|room=s' 				=> \$options{user},
	'd|download|download-images'	=> \$options{download_images},
	'h|help' 						=> \&show_help,
	'hp|hide-progress'				=> \$options{hide_progress},
	'sj|save|save-json'				=> \$options{save_json},
	'o|overwrite'					=> \$options{overwrite},
	'nd|no-dump'					=> \$options{no_dump},
	't|timeout=i'					=> \$options{timeout},
	'p|proxy=s'						=> \$options{proxy},
	'l|loop'	=> \$options{loop},
	's|sleep=i' => \$options{sleep_interval},
);


unless(defined $options{user}){
	die "No room specified\n";
}

my $uname = $options{user};

my $url = $options{api_url};
$url =~ s/\=USER\=/$uname/;

if($options{hide_progress}){
	$mech_options{show_progress} = 0;
}
if($options{timeout} > 0){
	$mech_options{timeout} = $options{timeout};
}
if(defined $options{proxy}){
	unless($options{proxy} =~ /^(\d{1,}\.){3}\d{1,3}\:\d+$/){
		print "Proxy is in an invalid format.\nValid format is: <ip>:<port>";
		exit;
	}
	$options{proxy} = 'socks://' . $options{proxy};
	print "Using proxy: $options{proxy}\n";
}

&run;

if($options{loop}){
	while(1){
		sleep($options{sleep_interval});
		&run;
	}
}

sub run
{

my $js = download_json($url);
#print Dumper($js),"\n";
my $json; 
eval{$json = decode_json($js);};
if(my $err = $@){
	print "Error decoding JSON.\n$err\n";
	exit;
}
#print Dumper($json),"\n"; 
#exit;
unless(defined $json){
	die "Problem parsing JSON\n";
}elsif(exists $json->{error}){
	die "Error fetching information: " . $json->{error} . "\n";
}

if($options{save_json})
{
	my $json_encoder = new JSON;
	$json_encoder = $json_encoder->utf8(1);
	$json_encoder = $json_encoder->pretty(1);
	$json_encoder = $json_encoder->canonical(1);
	my $json_str = $json_encoder->encode($json);

	my $json_dir = $main_dir . "json/";
	unless(-e $json_dir){
		create_directory($json_dir);
	}
	my $json_file = $json_dir . $uname . '.json';
	if(!$options{overwrite})
	{
		my $i = 1;
		$json_file = $json_dir . "$uname-$i.json";
		while(-e $json_file)
		{
			$json_file = $json_dir . "$uname-$i.json";
			$i++;
		}
	}
	print "\nSaving JSON to $json_file\n";
	open(F, '>:utf8', $json_file) or die "Error opening JSON file \"$json_file\": $!\n";
	print F $json_str;
	close(F);
}

my $member_name = "";
my $name = "";
my $mod_count = 0;
my $broadcaster_count = 0;
my @users = ();
my @pics = ();

if(exists $json->{member_name}){
	$member_name = $json->{member_name};
}
if(exists $json->{name}){
	$name = $json->{name};
}
if(exists $json->{mod_count}){
	$mod_count = $json->{mod_count};
}
if(exists $json->{broadcaster_count}){
	$broadcaster_count = $json->{broadcaster_count};
}
if(exists $json->{names} && @{$json->{names}}){
	@users = 
		sort{lc($a) cmp lc($b)}
		@{$json->{names}};
}
if(exists $json->{pic} && @{$json->{pic}}){
	@pics = 
		sort{lc($a) cmp lc($b)}
		grep{length $_}
		grep{defined $_}
		@{$json->{pic}};
}

if(!$options{no_dump})
{
	print "\n";
	print "Room: $uname\n";
	print "Member name: $member_name\n";
	print "Name: $name\n";
	print "Mod count: $mod_count\n";
	print "Broadcaster count: $broadcaster_count\n";
	
	unless(@users){
		print "\nNo users found\n";
	}else{
		print "\nUsers:\n";
		for my $user(@users){
			print "\t$user\n";
		}
	}
	
	unless(@pics){
		print "\nNo pictures found\n";
	}else{
		print "\nPicture urls:\n";
		for my $pic(@pics){
			print "\t$pic\n";
		}
	}
}

if($options{download_images})
{
	if(@pics)
	{
		my $img_dir = $main_dir . "images/$uname/";
		unless(-e $img_dir){
			create_directory($img_dir);
		}

		print "\nDownloading images...\n";
		for my $pic(@pics)
		{
			my ($fname, undef) = fileparse($pic);
			unless(defined $fname)
			{
				my $i = 1;
				$fname = $img_dir . "$uname-$i.jpg";
				while(-e $fname){
					$fname = $img_dir . "$uname-$i.jpg";
					$i++;
				}
			}else{
				$fname = $img_dir . $fname;
			}
			#Don't overwrite
			if(!$options{overwrite})
			{
				if(-e $fname)
				{
					my($f, undef, $ext) = fileparse($pic, qr/\.[^.]*/);
					my $i = 1;
					my $new_fname = $img_dir . "$f-$i$ext";
					while(-e $new_fname){
						$new_fname = $img_dir . "$f-$i$ext";
						$i++;
					}
					$fname = $new_fname;
					#print "$d | $f | $ext\n";
				}
			}
			download_image($pic, $fname);
		}
	}
}

}

sub download_json($)
{
	my $mech = WWW::Mechanize::GZip->new(%mech_options);
	if(defined $options{proxy})
	{
		$mech->proxy(['http', 'https'] => $options{proxy}); 
		$mech->no_proxy('localhost', '127.0.0.1');
	}
	my $response = $mech->get($url);
	unless($mech->success()){
		die "Unable to fetch page: ",  $response->status_line,"\n";
	}
	my $content = $response->content;
	undef $mech;
	return $content;
}

#'http://upload.tinychat.com/i/roomname-user.jpg' 

sub download_image($$)
{
	my ($file_url, $file_name) = @_;

	my $mech = WWW::Mechanize::GZip->new(%mech_options);
	if(defined $options{proxy})
	{
		$mech->proxy(['http', 'https'] => $options{proxy}); 
		$mech->no_proxy('localhost', '127.0.0.1');
	}
	my $response = $mech->get($file_url);
	unless($mech->success()){
		print "Error: $file_url\n\t|_-> Unable to fetch page ",  $response->status_line,"\n\n";
		return 0;
	}else{
		$mech->save_content($file_name);
		print "Saved $file_url\n\t|_-> $file_name\n\n";
		return 1;
	}
	
}

sub cd(;$)
{
	my $dir = $_[0];
	unless(defined $dir){
		(undef, $dir) = fileparse(abs_path($0));
	}
	$dir =~ s/\\+/\//g;
	chdir($dir) or die "Can't change CWD directory to $dir: $!\n";
	#print "Changed CWD to: \"$dir\"\n";
}

sub get_cwd
{
	my (undef, $dir) = fileparse(abs_path($0));
	if(defined $dir){
		$dir =~ s/\\/\//g;
		if($dir !~ /\/$/){
			$dir .= "/";
		}
	}
	return $dir;
}

sub create_directory($)
{
	my $dir_to_create = $_[0];
	File::Path::make_path
	(
		$dir_to_create,
		{
			error   => \my $err,
			verbose => 1
		}
	);
	if(@$err)
	{
		#print Dumper($err);
		for my $diag (@$err)
		{
				my ($file, $message) = %$diag;
				if ($file eq ''){
						print "Error: $message\n";
				}else{
					print "Error: problem unlinking $file: $message\n";
				}
		}
		#die "Directory $dir_to_create could not be created\n";
		return 0;
	}
	else
	{
		print "Info: created $dir_to_create\n";
		return 1;
	}
}

sub show_help
{

print <<EOL;

Options:
   -d  | -download         - Download user images.
   -h  | -help             - Show help menu and exit.
   -hp | -hide-progress    - Do not show download progress.
   -l  | -loop             - Fetch continously. Use -s to set the interval.   
   -nd | -no-dump          - Do not show information found.
   -o  | -overwrite        - Overwrite existing files when saving content.
   -p  | -proxy            - Use proxy to download through.
                             Valid format: <ip>:<port>
   -s  | -sleep            - Sleep interval when -l is used. 
   -sj | -save             - Save downloaded JSON to file.
   -t  | -timeout          - Set download timeout.
   -u  | -user|-r|-room    - The room name to get information of.
	
EOL

	exit;
}
