use strict;
use Data::Dumper;
my %adj0;
my %adj1;
my %subst0;

my $f="src/insult.txt";
open IN,"<",$f or die "cannot open $f, stopping";
while(<IN>){
   chomp;
   my ($w0,$w1,$w2)=split /,/;
   $adj0{ucfirst(lc($w0))}=1;
   $adj1{ucfirst(lc($w1))}=1;
   $subst0{ucfirst(lc($w2))}=1;
}
close IN;
#print Dumper(\%adj0);
#print Dumper(\%adj1);
#print Dumper(\%subst0);
for my $w0(sort keys %adj0){
   for my $w1(sort keys %adj1){
      for my $w2(sort keys %subst0){
         print "Thou$w0$w1$w2\n";
      }
   }
}

