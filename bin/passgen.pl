#!/usr/bin/perl
# passgen.pl - generate passwords from Shakespearean insults, English words
# or random characters.
#
# Each part of the password is picked with a cryptographically secure
# random source, and the estimated strength (entropy in bits) is printed
# to STDERR so it does not end up in a pipe or file.
#
# Run "perl bin/passgen.pl --help" for usage.
#
# Rewritten with AI assistance (Claude, Anthropic); reviewed and tested by Erlend Leganger.

use strict;
use warnings;
use FindBin;
use File::Spec;
use Getopt::Long qw(:config no_ignore_case bundling);
use List::Util qw(uniq min max sum);

$| = 1;   # keep passwords and strength line in order on screen

my $root = File::Spec->catdir($FindBin::Bin, File::Spec->updir);

my $SYMBOLS = '!#$%&*+-=?@^_~';
my %CLASS = (
   lower  => join('', 'a' .. 'z'),
   upper  => join('', 'A' .. 'Z'),
   digit  => join('', 0 .. 9),
   symbol => $SYMBOLS,
);

# Options are read into %opt; anything not given stays undef so that
# --fit only fills in what the user did not set explicitly.
my %opt;
GetOptions(
   's|source=s' => \$opt{source},
   'w|words=i'  => \$opt{words},
   'min=i'      => \$opt{min},
   'max=i'      => \$opt{max},
   'd|digits=i' => \$opt{digits},
   'S|symbol!'  => \$opt{symbol},
   'm|maxlen=i' => \$opt{maxlen},
   'f|fit=i'    => \$opt{fit},
   'l|length=i' => \$opt{length},
   'n|count=i'  => \$opt{count},
   'q|quiet'    => \$opt{quiet},
   'h|help'     => sub { usage(0) },
) or usage(1);
die "Unexpected argument(s): @ARGV (see --help)\n" if @ARGV;

apply_fit(\%opt) if defined $opt{fit};

$opt{source} //= 'insult';
$opt{words}  //= 4;
$opt{min}    //= 4;
$opt{max}    //= 8;
$opt{digits} //= 4;
$opt{symbol} //= 0;
$opt{count}  //= 1;

die "--digits must be 0 or more\n" if $opt{digits} < 0;
die "--count must be 1 or more\n"  if $opt{count} < 1;

my $rng = open_rng();

if ($opt{source} eq 'random') {
   random_mode();
}
elsif ($opt{source} eq 'insult' || $opt{source} eq 'english') {
   word_mode();
}
else {
   die "--source must be 'insult', 'english' or 'random'\n";
}
exit 0;

# --- modes -----------------------------------------------------------------

# --fit N: sensible defaults for a site that allows at most N characters.
# Words: English, 4 digits, one symbol, and as many words (1-4) as the
# remaining letters comfortably allow. Random: N characters.
sub apply_fit {
   my ($o) = @_;
   my $n = $o->{fit};
   $o->{source} //= 'english';
   if ($o->{source} eq 'random') {
      $o->{length} //= $n;
      return;
   }
   $o->{maxlen} //= $n;
   $o->{digits} //= 4;
   $o->{symbol} //= 1;
   my $letters = $o->{maxlen} - $o->{digits} - ($o->{symbol} ? 1 : 0);
   $o->{words} //= max(1, min(4, int($letters / 5)));
}

sub word_mode {
   my @lists;
   my $what;
   if ($opt{source} eq 'insult') {
      @lists = load_insult(File::Spec->catfile($root, 'src', 'insult.txt'));
      $what  = 'insult adjective + adjective + noun';
   }
   else {
      die "--words must be 1 or more\n" if $opt{words} < 1;
      die "--min must be 1 or more and not above --max\n"
         if $opt{min} < 1 || $opt{min} > $opt{max};
      my $words = load_english(File::Spec->catfile($root, 'src', 'english3.txt'),
                               $opt{min}, $opt{max});
      @lists = ($words) x $opt{words};
      $what  = "$opt{words} English word" . ($opt{words} > 1 ? 's' : '')
             . " ($opt{min}-$opt{max} letters)";
   }

   my $tail = $opt{digits} + ($opt{symbol} ? 1 : 0);
   my $budget;                      # max letters for the words, if capped
   my $fit_bits;                    # log2 of word combinations that fit
   if (defined $opt{maxlen}) {
      $budget = $opt{maxlen} - $tail;
      die "--maxlen $opt{maxlen} leaves no room for words after "
        . "$opt{digits} digits" . ($opt{symbol} ? ' and a symbol' : '') . "\n"
         if $budget < 1;
      # Drop words that can never fit, given the shortest word in every
      # other position. This does not change which passwords are possible.
      my @short = map { min map { length } @$_ } @lists;
      my $all   = sum @short;
      for my $i (0 .. $#lists) {
         my $room = $budget - ($all - $short[$i]);
         $lists[$i] = [ grep { length($_) <= $room } @{ $lists[$i] } ];
      }
      $fit_bits = log2_fitting(\@lists, $budget);
      die "No combination of $what fits in $opt{maxlen} characters. "
        . "Try fewer --words, fewer --digits or a larger --maxlen.\n"
         unless defined $fit_bits;
      $what .= " within $budget letters";
   }

   for (1 .. $opt{count}) {
      # With a length cap: pick freely and keep only if it fits
      # (rejection sampling), so every password that fits is equally likely.
      my @words;
      do {
         @words = map { $_->[ pick(scalar @$_) ] } @lists;
      } while (defined $budget && sum(map { length } @words) > $budget);
      my $pw = join '', map { ucfirst } @words;
      $pw .= pick(10) for 1 .. $opt{digits};
      $pw .= substr($SYMBOLS, pick(length $SYMBOLS), 1) if $opt{symbol};
      print "$pw\n";
   }

   return if $opt{quiet};
   my $bits = defined $budget
            ? $fit_bits
            : sum map { log2(scalar @$_) } @lists;
   $bits += $opt{digits} * log2(10);
   $bits += log2(length $SYMBOLS) if $opt{symbol};
   $what .= " + $opt{digits} digit" . ($opt{digits} == 1 ? '' : 's') if $opt{digits};
   $what .= ' + symbol' if $opt{symbol};
   report($bits, $what);
}

# Random characters: always at least one lower case letter, upper case
# letter, digit and symbol, since many sites require that.
sub random_mode {
   my $len = $opt{length} // $opt{maxlen} // 16;
   my @classes = map { $CLASS{$_} } qw(lower upper digit symbol);
   die "--length must be at least " . scalar(@classes) . "\n" if $len < @classes;
   my $set = join '', @classes;

   for (1 .. $opt{count}) {
      my $pw;
      do {
         $pw = join '', map { substr($set, pick(length $set), 1) } 1 .. $len;
      } until (all_classes($pw, @classes));
      print "$pw\n";
   }

   return if $opt{quiet};
   report(log2(count_random(\@classes, $len)),
          "$len random characters from a-z A-Z 0-9 $SYMBOLS, all four kinds");
}

# --- word lists ------------------------------------------------------------

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
   my ($file, $lo, $hi) = @_;
   open my $in, '<', $file or die "Cannot open $file: $!\n";
   my @w;
   while (my $line = <$in>) {
      $line =~ s/\s+\z//;
      push @w, $line if $line =~ /^[a-z]{$lo,$hi}\z/;
   }
   close $in;
   @w = uniq @w;
   die "No words of length $lo-$hi in $file\n" unless @w;
   return \@w;
}

# --- counting (for the strength estimate) ----------------------------------

# log2 of the number of word combinations, one word per list, whose total
# length is at most $budget (undef if none fit). Counted by length, so it is
# fast even for big lists. Works with fractions of each list instead of raw
# counts, because the raw counts can overflow Perl's 64-bit integers.
sub log2_fitting {
   my ($lists, $budget) = @_;
   my %share = (0 => 1);            # total length => fraction of combinations
   for my $l (@$lists) {
      my %hist;
      $hist{ length $_ }++ for @$l;
      my $n = @$l;
      my %next;
      for my $t (keys %share) {
         for my $len (keys %hist) {
            $next{ $t + $len } += $share{$t} * ($hist{$len} / $n)
               if $t + $len <= $budget;
         }
      }
      %share = %next;
   }
   my $frac = sum(0, values %share);
   return undef if $frac <= 0;
   return log2($frac) + sum map { log2(scalar @$_) } @$lists;
}

# Number of strings of length $len over all classes that contain at least
# one character of every class (inclusion-exclusion over missing classes).
sub count_random {
   my ($classes, $len) = @_;
   my $total = 0;
   my $k = @$classes;
   for my $mask (0 .. 2**$k - 1) {
      my ($size, $missing) = (0, 0);
      for my $i (0 .. $k - 1) {
         if ($mask & (1 << $i)) { $missing++ }
         else                   { $size += length $classes->[$i] }
      }
      $total += (-1)**$missing * $size**$len;
   }
   return $total;
}

sub all_classes {
   my ($pw, @classes) = @_;
   for my $c (@classes) {
      return 0 unless $pw =~ /[\Q$c\E]/;
   }
   return 1;
}

# --- randomness ------------------------------------------------------------

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
   my ($n) = @_;
   die "Cannot pick from an empty list\n" if $n < 1;
   my $range = 2**32;
   my $limit = $range - ($range % $n);
   while (1) {
      my $r = unpack 'N', $rng->(4);
      return $r % $n if $r < $limit;
   }
}

# --- output ----------------------------------------------------------------

sub log2 { log($_[0]) / log(2) }

sub report {
   my ($bits, $what) = @_;
   my $rating = $bits < 40 ? 'weak: fine against online guessing only'
              : $bits < 60 ? 'moderate'
              :              'strong';
   printf STDERR "Strength: ~%.0f bits (%s)\n          %s\n", $bits, $rating, $what;
}

sub usage {
   my ($exit) = @_;
   print <<"END";
Usage: perl bin/passgen.pl [options]

Source:
  -s, --source NAME   insult (default), english or random
                        insult:  adjective + adjective + noun from src/insult.txt
                        english: random words from src/english3.txt
                        random:  random characters, always with at least one
                                 lower, upper, digit and symbol

Words (insult and english):
  -w, --words N       number of words, english only (default 4)
      --min N         shortest English word (default 4)
      --max N         longest English word (default 8)
  -d, --digits N      random digits to append (default 4, 0 for none)
  -S, --symbol        append one random symbol from $SYMBOLS
  -m, --maxlen N      whole password at most N characters; only word
                      combinations that fit are used

Random characters:
  -l, --length N      number of characters (default 16)

Site limits:
  -f, --fit N         sensible password for a site allowing at most N
                      characters. Default source is english with 4 digits,
                      a symbol and 1-4 words (as many as fit well); with
                      -s random it gives N random characters. Any option
                      you give yourself overrides these defaults.

Other:
  -n, --count N       number of passwords to generate (default 1)
  -q, --quiet         do not print the strength estimate
  -h, --help          show this help

The strength estimate is printed to STDERR, so piping or redirecting
the output only captures the passwords.

Examples:
  perl bin/passgen.pl
  perl bin/passgen.pl -S -n 5
  perl bin/passgen.pl -s english -w 4 -d 2 -S
  perl bin/passgen.pl --fit 20
  perl bin/passgen.pl --fit 20 -w 2
  perl bin/passgen.pl -s random -l 12
END
   exit $exit;
}
