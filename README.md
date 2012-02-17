SilverStripe Randomiser
=======================

Works with Mateusz's testdata module (see below).  
This script produces random objects and inspecs the database to find types and columns for the class.

Basic usage will simply generate data for all columns found in the relevant table, trying to guess the data-type
from the DB information and some heuristics.
However, a large number of switches make it easy to generate data with more specific data definition.

Use the `--help` argument for detailed usage information.

Author: Luke Hudson <lukeletters@gmail.com>

Basic usage
-----------

     user@host:~/$ ./strandd.pl MyCustomPage 10 --inherit SiteTree \
         --include Created,Title,Content --columns CustomFieldID:Reln --maptable CustomFieldID:Member

This would create 10 randomised objects of type MyCustomPage, which inherits from SiteTree.
We only inlcude the Created,Title and Content fields from the original object, but then also add
The CustomFieldID, specifying that it's a relationship, and that we should find IDs for this relation
from the Member table.


Requirements
------------

### Perl modules ###

 * Date::Manip
 * YAML::Tiny
 * Getopt::Declare
 * DBI

### Loading data ###

To load the data produced, use the very handy [testdata module][testdata] maintained by Mateusz Uzdowski

[testdata]: http://github.com/mateusz/silverstripe-testdata