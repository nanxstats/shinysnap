# The client-side script as an HTML dependency

The `snap_*()` server functions inject this script into the page on
first use, so including it in the UI is optional. Include it explicitly
when you want the script to load with the page, before the server
function runs.

## Usage

``` r
snap_dependency()
```

## Value

An
[`htmltools::htmlDependency()`](https://rstudio.github.io/htmltools/reference/htmlDependency.html).

## Examples

``` r
snap_dependency()
#> List of 10
#>  $ name      : chr "shinysnap"
#>  $ version   : chr "0.1.0"
#>  $ src       :List of 1
#>   ..$ file: chr "/home/runner/work/_temp/Library/shinysnap/www"
#>  $ meta      : NULL
#>  $ script    : chr "shinysnap.js"
#>  $ stylesheet: NULL
#>  $ head      : NULL
#>  $ attachment: NULL
#>  $ package   : NULL
#>  $ all_files : logi TRUE
#>  - attr(*, "class")= chr "html_dependency"
```
