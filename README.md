# airprint-ppd.zsh

This script generates a PPD for AirPrint capable printers. It is based on the work of [Kevin M. Cox](https://www.kevinmcox.com/2020/12/airprint-generator/) and [Apizz](https://aporlebeke.wordpress.com/2019/10/30/configuring-printers-programmatically-for-airprint/) and solves the problem with missing Printer icons when working in root context.

It will fetch all printer icon files from the printer via HTTP and will then try to build an iconset, which will then be converted to a icns file and stored to `/Library/Printers/Icons` with a predefined name.

## Usage

This script queries the given printer url for a PPD and handles the icon generation, so that it may be run as root. A printer icon will be generated and saved to the default location with the expected name containing the printers UUID. You may optionally save a copy of the icons file to a different location.

    airprint-ppd.zsh -p printer_url [-i icns_copy_dir] [-o ppd_output_dir] [-n name] [-s]

### Parameters

* `-p printer_url`: IPP URL, for example ipp://FNCYPRNTR.local or ipp://192.168.1.244:443 (mandatory)
* `-i icns_copy_dir`: Output directory to copy the printer icon to, required if not running with root privileges
* `-o ppd_output_dir`: Output dir for PPD, required if not running with root privileges. For root user this defaults to `/Library/Printers/PPDs/Contents/Resources`
* `-n name`: Name to be used for icon and ppd file, defaults to queried model name
* `-s`: Switch to secure mode, which won't ignore untrusted TLS certificates
* `-h`: Show usage message

So, when running this script without root privileges, you are required to specify all three parameters. Running as root enables you to use the default directories for the printer icon and the PPD file.

## System Requirements

This script was tested with macOS 10.15 Catalina and macOS 11 Big Sur. It should work with macOS 10.14 Mojave, but this is not verified.

It uses only default system components and (hopefully) no third party tools.

We have successfully worked with different make and models, but there may be some printers who react unexpectedly to our requests – so please test this script and provide some feedback when you encounter any problems.

## Caveats

Some printers have disabled unencrypted IPP traffic but do not present a trusted TLS certificate. To properly download the needed icon images anyway, we are running the `curl` command with the `insecure` option by default. So please, **query trusted IPP addresses, only**. You may use the `-s` option to force the certificate validation.
