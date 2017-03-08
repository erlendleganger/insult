Usage

#generate, print on stdout
perl bin/insult.pl 

#generate, save to file
perl bin/insult.pl >out/insult-list.txt

#generate, pick one entry
perl bin/insult.pl | shuf -n 1

#pick one from generated file
shuf -n 1 out/insult-list.txt

