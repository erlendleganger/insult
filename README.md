<!-- Created with AI assistance (Claude, Anthropic); reviewed and tested by Erlend Leganger. -->

# insult

A small Perl command-line password generator. It builds passwords from
Shakespearean insults (just for fun), from random English words, or from
random characters. It also prints an estimate of how strong each password is.

```console
$ perl bin/passgen.pl --fit 20
SteamMoupsChich3379&
Strength: ~61 bits (strong)
          3 English words (4-8 letters) within 15 letters + 4 digits + symbol
```

## Features

- **Three sources:** Shakespearean insult words (the default, for fun),
  English words, or random characters.
- **Length limits (`--fit N`):** picks sensible defaults for a site that
  allows at most N characters. Only passwords that fit are generated, and
  every password that fits is equally likely.
- **Secure randomness:** uses `Crypt::URandom` or `/dev/urandom`, picks with
  rejection sampling so there is no modulo bias, and never falls back to
  Perl's `rand()`.
- **Strength estimate:** the entropy in bits is printed to STDERR, so it does
  not end up in a pipe or file.
- **Random mode meets common site rules:** it always includes at least one
  lower case letter, upper case letter, digit and symbol.

## Requirements

- Perl 5.26 or newer (it needs `uniq` from the core module `List::Util`).
- A secure random source. Either of these works:
  - `/dev/urandom`, which is available in Git Bash on Windows, Linux and macOS, or
  - the CPAN module [Crypt::URandom](https://metacpan.org/pod/Crypt::URandom),
    installed with `cpan Crypt::URandom`.

No other modules are needed.

## Installation

```bash
git clone git@github.com:erlendleganger/insult.git
cd insult
perl bin/passgen.pl --help
```

The script finds its word lists relative to its own location, so you can run
it from any directory.

## Usage

```text
perl bin/passgen.pl [options]
```

| Option | Description |
| --- | --- |
| `-s`, `--source NAME` | `insult` (default), `english` or `random` |
| `-w`, `--words N` | number of English words (default 4) |
| `--min N` / `--max N` | shortest / longest English word (default 4 / 8) |
| `-d`, `--digits N` | random digits to append (default 4, 0 for none) |
| `-S`, `--symbol` | append one random symbol (`--no-symbol` turns it off) |
| `-m`, `--maxlen N` | whole password at most N characters |
| `-l`, `--length N` | length in random mode (default 16) |
| `-f`, `--fit N` | sensible password for a site allowing at most N characters |
| `-n`, `--count N` | number of passwords to generate (default 1) |
| `-q`, `--quiet` | do not print the strength estimate |
| `-h`, `--help` | show help |

With `--fit`, any option you give yourself overrides the defaults it picks.

### Examples

| Command | Result | Strength |
| --- | --- | --- |
| `perl bin/passgen.pl` | insult adjective + adjective + noun + 4 digits | ~31 bits |
| `perl bin/passgen.pl --fit 16` | 2 English words + 4 digits + symbol | ~47 bits |
| `perl bin/passgen.pl --fit 20` | 3 English words + 4 digits + symbol | ~61 bits |
| `perl bin/passgen.pl --fit 20 --no-symbol` | same, for sites that forbid symbols | ~58 bits |
| `perl bin/passgen.pl -s english -S` | 4 English words + 4 digits + symbol | ~83 bits |
| `perl bin/passgen.pl -s random` | 16 random characters | ~100 bits |
| `perl bin/passgen.pl -s random --fit 12` | 12 random characters | ~75 bits |

Generate several and keep the one that is easiest to remember. With five to
choose from, this costs only about 2 bits:

```bash
perl bin/passgen.pl --fit 20 -n 5
```

To save passwords to a file (the strength line is not included):

```bash
perl bin/passgen.pl --fit 20 -n 10 > tmp/passwords.txt
```

See [misc/paste-library.txt](misc/paste-library.txt) for more ready-to-paste commands.

## How strong is strong enough?

The script uses this rough guide: under 40 bits is weak, 40–60 bits is
moderate, and 60 bits or more is strong. Insult passwords (~31–35 bits) are
for fun and only resist online guessing. Use `--fit` or `-s english` for real
accounts, and `-s random` for passwords kept in a password manager.

## Project layout

```text
bin/passgen.pl            the generator
src/insult.txt            insult words: adjective, compound adjective, noun per line
src/english3.txt          English word list (~194,000 words)
src/english3-length-NN.txt  the same list split by word length
misc/                     notes and a library of example commands
tmp/                      scratch output (ignored by git)
```

## Word lists

The English word list comes from
[gwicks.net](http://www.gwicks.net/dictionaries.htm). See
[misc/notes.txt](misc/notes.txt) for how the per-length files were made.

## AI assistance

Parts of this project, including `bin/passgen.pl` and this README, were
developed with the help of Claude (Anthropic). All changes were reviewed and
tested by the author. Files made or largely rewritten with AI assistance have
a header comment that says so.

## License

No license has been chosen yet. Until one is added, normal copyright
applies.
