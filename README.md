SilverStripe Randomiser
=======================

Works with Mateusz's testdata module (see below).  
This script produces random objects and inspecs the database to find types and columns for the class.

Basic usage will simply generate data for all columns found in the relevant table, trying to guess the data-type
from the DB information and some heuristics.
However, a large number of switches make it easy to generate data with more specific data definition.

Use the `--help` argument for detailed usage information.

Author: Luke Hudson <lukeletters@gmail.com>

Usage examples
--------------

     user@host:~/$ ./strandd.pl MyCustomPage 10 --inherit SiteTree \
         --include Created,Title,Content \
         --columns CustomFieldID:Reln \
         --maptable CustomFieldID:Member

This would create 10 randomised objects of type MyCustomPage, which inherits from SiteTree.
We only inlcude the Created,Title and Content fields from the original object, but then also add
The CustomFieldID, specifying that it's a relationship, and that we should find IDs for this relation
from the Member table.

     user@host:~/$ ./strandd.pl BlogPost 50 \
         --include Created,Title,PostImageID,AuthorID,PostImageID \
         --columns Content:HtmlText:400 \
         --maptable AuthorID:Member \
         --many Tags:5  --imgdir PostImageID:blogimages

This example would create 50 items of type `BlogPost`.  We include only some of the default columns, but also provide 
some custom column mappings. We specify that the Content column shall be HtmlText of up to 400 characters.
We also add in a `has_many` (or `many_many`) relation in, specifying that the column Tags will have up to 5 items. 
By default these will be looked up in the table `Tag`, but we could have specified another table mapping `--maptable` 
if this were not the correct table.
We also tell the script to pick random images for the PostImageID field, but only to pick from files within `assets/blogimages`.
For this last to work, `sake dev/tasks/FilesystemSyncTask` needs to have been run before this script.


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