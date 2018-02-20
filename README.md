
For an overview of the project see [here](http://laneslexicon.github.io).

This repository should be used in conjuction with the laneslexicon/xml repository

```
project root
|
|--- documentation
|--- lexicon
|--- parser
|--- xml
```

Assuming this directory structure as above, to build a database

```
make -f util.mak build
```

This should build a database called 'lexicon.sqlite' assuming that the Perseus XML files are at ../xml and output a number of log files to a directory ../logs.

Edit the make file if these directories do not exist.

See [here](http://laneslexicon.github.io/lexicon/site/dev-guide/scripts/index.html) for a description of 'orths.pl'
