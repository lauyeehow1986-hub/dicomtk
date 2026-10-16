# Convert a DICOM File to XML (Native DICOM Model PS3.19)

Exports the DICOM header and dataset elements to XML format.

## Usage

``` r
dcm2xml(file, out_path = NULL, opts = "", ...)
```

## Arguments

- file:

  Path to input DICOM file.

- out_path:

  Optional output `.xml` file path. If `NULL` (default), writes to a
  temporary `.xml` file and returns its path (with the XML string
  attached as attribute `"xml"`).

- opts:

  Optional arguments (ignored in native C++ mode, kept for legacy
  compatibility).

- ...:

  Additional unused arguments.

## Value

Character string of the output `.xml` file path.

## Examples

``` r
dcm_file <- system.file("extdata", "example.dcm", package = "dicomtk")
xml_file <- dcm2xml(dcm_file)
head(readLines(xml_file), 10)
#>  [1] "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"                                              
#>  [2] "<NativeDicomModel xml:space=\"preserve\">"                                               
#>  [3] "  <DicomAttribute tag=\"00020000\" vr=\"UL\" keyword=\"FileMetaInformationGroupLength\">"
#>  [4] "    <Value number=\"1\">192</Value>"                                                     
#>  [5] "  </DicomAttribute>"                                                                     
#>  [6] "  <DicomAttribute tag=\"00020001\" vr=\"OB\" keyword=\"FileMetaInformationVersion\">"    
#>  [7] "    <Value number=\"1\">00</Value>"                                                      
#>  [8] "    <Value number=\"2\">01</Value>"                                                      
#>  [9] "  </DicomAttribute>"                                                                     
#> [10] "  <DicomAttribute tag=\"00020002\" vr=\"UI\" keyword=\"MediaStorageSOPClassUID\">"       
```
