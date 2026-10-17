#!/usr/bin/perl
# insult.pl - generate passwords from Shakespearean insults or English words.
#
# Each part of the password is picked independently with a cryptographically
# secure random source, and the estimated strength (entropy in bits) is
# printed to STDERR so it does not end up in a pipe or file.
#
# Run "perl bin/insult.pl --help" for usage.

use strict;
use warnings;
use FindBin;
use File::Spec;
use Getopt::Long qw(:config no_ignore_case bundling);
use List::Util qw(uniq);

$| = 1;   # keep passwords and strength line in order on screen

my $root = File::Spec->catdir($FindBin::Bin, File::Spec->updir);

my %opt = (
   source  => 'insult',
   words   => 4,
   min     => 4,
   max     => 8,
   digits  => 4,
   symbol  => 0,
   count   => 1,
   quiet   => 0,
);
my $symbols = '!#$%&*+-=?@^_~';

GetOptions(
   's|source=s' => \$opt{source},
   'w|words=i'  => \$opt{words},
   'min=i'      => \$opt{min},
   'max=i'      => \$opt{max},
   'd|digits=i' => \$opt{digits},
   'S|symbol!'  => \$opt{symbol},
   'n|count=i'  => \$opt{count},
   'q|quiet'    => \$opt{quiet},
   'h|help'     => sub { usage(0) },
) or usage(1);

die "--digits must be 0 or more\n" if $opt{digits} < 0;
die "--count must be 1 or more\n"  if $opt{count} < 1;

# Build the word lists: one list per word position in the password.
my @lists;
if ($opt{source} eq 'insult') {
   @lists = load_insult(File::Spec->catfile($root, 'src', 'insult.txt'));
}
elsif ($opt{source} eq 'english') {
   die "--words must be 1 or more\n" if $opt{words} < 1;
   die "--min must be 1 or more and not above --max\n"
      if $opt{min} < 1 || $opt{min} > $opt{max};
   my $words = load_english(File::Spec->catfile($root, 'src', 'english3.txt'),
                            $opt{min}, $opt{max});
   @lists = ($words) x $opt{words};
}
else {
   die "--source must be 'insult' or 'english'\n";
}

my $rng = open_rng();

for (1 .. $opt{count}) {
   my $pw = join '', map { ucfirst $_->[ pick($rng, scalar @$_) ] } @lists;
   $pw .= pick($rng, 10) for 1 .. $opt{digits};
   $pw .= substr($symbols, pick($rng, length $symbols), 1) if $opt{symbol};
   print "$pw\n";
}

unless ($opt{quiet}) {
   my $bits = 0;
   $bits += log2(scalar @$_) for @lists;
   $bits += $opt{digits} * log2(10);
   $bits += log2(length $symbols) if $opt{symbol};
   my $rating = $bits < 40 ? 'weak: fine against online guessing only'
              : $bits < 60 ? 'moderate'
              :              'strong';
   printf STDERR "Strength: ~%.0f bits (%s); word lists: %s\n",
      $bits, $rating, join(' x ', map { scalar @$_ } @lists);
}

# --- subroutines -----------------------------------------------------------

# insult.txt: three comma-separated columns per line
# (adjective, compound adjective, noun); each column is its own list.
sub load_insult {
   my ($file) = @_;
   my @col = ([], [], []);
   open my $in, '<', $file or die "Cannot open $file: $!\n";
   while (my $line = <$in>) {
      $line =~ s/\s+\z//;
      next if $line eq '' || $line =~ /^#/;
      my @w = split /\s*,\s*/, lc $line;
      die "$file line $.: expected 3 words, got " . scalar(@w) . "\n" if @w != 3;
      push @{ $col[$_] }, $w[$_] for 0 .. 2;
   }
   close $in;
   return map { [ uniq @$_ ] } @col;
}

# english3.txt: one word per line; keep only a-z words of the given lengths.
sub load_english {
   my ($file, $min, $max) = @_;
   open my $in, '<', $file or die "Cannot open $file: $!\n";
   my @w;
   while (my $line = <$in>) {
      $line =~ s/\s+\z//;
      push @w, $line if $line =~ /^[a-z]{$min,$max}\z/;
   }
   close $in;
   @w = uniq @w;
   die "No words of length $min-$max in $file\n" unless @w;
   return \@w;
}

# Secure random bytes: Crypt::URandom if installed, otherwise /dev/urandom
# (available in Git Bash, Linux and macOS). Never falls back to rand().
sub open_rng {
   if (eval { require Crypt::URandom; 1 }) {
      return sub { Crypt::URandom::urandom($_[0]) };
   }
   if (open my $fh, '<:raw', '/dev/urandom') {
      return sub {
         my $n = $_[0];
         read($fh, my $buf, $n) == $n or die "Short read from /dev/urandom\n";
         return $buf;
      };
   }
   die "No secure random source found. Run from Git Bash, or install\n"
     . "Crypt::URandom (cpan Crypt::URandom).\n";
}

# Uniform random integer in 0 .. $n-1, using rejection sampling so that
# no value is more likely than another.
sub pick {
   my ($rng, $n) = @_;
   die "Cannot pick from an empty list\n" if $n < 1;
   my $range = 2**32;
   my $limit = $range - ($range % $n);
   while (1) {
      my $r = unpack 'N', $rng->(4);
      return $r % $n if $r < $limit;
   }
}

sub log2 { log($_[0]) / log(2) }

sub usage {
   my ($exit) = @_;
   print <<"END";
Usage: perl bin/insult.pl [options]

Options:
  -s, --source NAME   insult (default) or english
                        insult:  adjective + adjective + noun from src/insult.txt
                        english: random words from src/english3.txt
  -w, --words N       number of words, english only (default 4)
      --min N         shortest English word (default 4)
      --max N         longest English word (default 8)
  -d, --digits N      random digits to append (default 4, 0 for none)
  -S, --symbol        append one random symbol from $symbols
  -n, --count N       number of passwords to generate (default 1)
  -q, --quiet         do not print the strength estimate
  -h, --help          show this help

The strength estimate is printed to STDERR, so piping or redirecting
the output only captures the passwords.

Examples:
  perl bin/insult.pl
  perl bin/insult.pl -S -n 5
  perl bin/insult.pl -s english -w 4 -d 2 -S
END
   exit $exit;
}
