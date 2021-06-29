#!/bin/zsh
#
# Tool to generate a proper PPD and Icon file for a given AirPrint supported printer
#
# Special props to:
#     Kevin M. Cox: https://www.kevinmcox.com/2020/12/airprint-generator/
#     Apizz: https://aporlebeke.wordpress.com/2019/10/30/configuring-printers-programmatically-for-airprint/
#
# Author: choules@wycomco.de
# Last Update: 2021-06-29
#
##################################################################

ICNS_COPY_DIR=""
PPD_OUTPUT_DIR="/Library/Printers/PPDs/Contents/Resources"
PRINTER_URL=""
OUTPUT_NAME=""
SECURE_MODE=false

SCRIPT_NAME=`basename $0`
IPP2PPD="/System/Library/Printers/Libraries/ipp2ppd"
IPPTOOL="/usr/bin/ipptool"
AIRPRINT_PPD="/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/PrintCore.framework/Versions/A/Resources/AirPrint.ppd"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} -p printer_url [-i icns_copy_dir] [-o ppd_output_dir] [-n name] [-s]

This script queries the given printer url for a PPD and handles the icon generation, so that it may
be run as root. A printer icon will be generated and saved to the default location with the expected
name containing the printers UUID. You may optionally save a copy of the icons file to a different 
location.

    -p printer_url        IPP URL, for example ipp://FNCYPRINT.local or ipp://192.168.1.244:443, mandatory
    -i icns_copy_dir      Output dir for copy of icon, required if not running with root privileges
    -o ppd_output_dir     Output dir for PPD, required if not running with root privileges.
                          For root user this defaults to /Library/Printers/PPDs/Contents/Resources
    -n name               Name to be used for icon and ppd file, defaults to queried model name
    -s                    Switch to secure mode, which won't ignore untrusted TLS certificates
    -h                    Show this usage message

EOF
}

get_ppd_string() {
    cat "$1" | grep -i "$2" | awk -F ": " '{ print $2 }' | tr -d '"'
}

get_ippinfo_string() {
    cat "$1" | grep -i "$2" | awk -F " = " '{ print $2 }'
}

while getopts "p:i:o:n:sh" option
do
    case $option in
        "p")
            PRINTER_URL="$OPTARG"
            ;;
        "i")
            ICNS_COPY_DIR="$OPTARG"
            ;;
        "o")
            PPD_OUTPUT_DIR="$OPTARG"
            ;;
        "n")
            OUTPUT_NAME="$OPTARG"
            ;;
        "s")
            SECURE_MODE=true
            ;;
        "h" | *)
            usage
            exit 1
            ;;
    esac
done
shift $(($OPTIND - 1))

if [ $# -ne 0 ]; then
    usage
    exit 1
fi

if [ "${PRINTER_URL}" = "" ]; then
    echo "ERROR: No Printer URL given" 1>&2
    echo ""
    usage
    exit 2
fi

case "$PRINTER_URL" in
*/)
    ;;
*)
    PRINTER_URL="${PRINTER_URL}/"
    ;;
esac

if [ "${ICNS_COPY_DIR}" != "" ] && [ ! -d "${ICNS_COPY_DIR}" ]; then
    echo "ERROR: Provided icns_copy_dir not a valid directory" 1>&2
    echo ""
    usage
    exit 3
fi

if [ "${ICNS_COPY_DIR}" = "" ] && [ $EUID -ne 0 ]; then
    echo "You have not provided a icns_copy_dir. Since you are not running this command as root"
    echo "we will not be able to save the icns file to its default location. Please specify a"
    echo "writeable icns_copy_dir."
    echo ""
    usage
    exit 4
fi

if [ "${PPD_OUTPUT_DIR}" != "" ] && [ ! -d "${PPD_OUTPUT_DIR}" ]; then
    echo "ERROR: Provided ppd_output_dir not a valid directory" 1>&2
    echo ""
    usage
    exit 5
fi

if [ "${PPD_OUTPUT_DIR}" = "" ] && [ $EUID -ne 0 ]; then
    echo "You have not provided a ppd_output_dir. Since you are not running this command as root"
    echo "we will not be able to save the ppd file to its default location. Please specify a"
    echo "writeable ppd_output_dir."
    echo ""
    usage
    exit 6
fi

echo "Creating a temporary working directory..."
TEMP_DIR=`mktemp -d`

if [ $? -ne 0 ]; then
    echo "$0: Can't create temporary directory, exiting..."
    exit 500
fi

echo "Created temporary directory at: ${TEMP_DIR}"
PPD_FILE="${TEMP_DIR}/printer.ppd"

echo "Fetching the PPD using ipp2ppd..."
"${IPP2PPD}" "${PRINTER_URL}" "${AIRPRINT_PPD}" > "${PPD_FILE}"

if [ ! -s "${PPD_FILE}" ]; then
    echo "ERROR: Fetched PPD is empty..."
    exit 404
fi

MODEL_NAME=`get_ppd_string "${PPD_FILE}" "ModelName"`
MANUFACTURER=`get_ppd_string "${PPD_FILE}" "Manufacturer"`
DEFAULT_ICON_PATH=`get_ppd_string "${PPD_FILE}" "APPrinterIconPath"`

IPPINFO_FILE="${TEMP_DIR}/ippinfo"

if [ "${OUTPUT_NAME}" = "" ]; then
    OUTPUT_NAME="${MODEL_NAME}"
fi

echo "Fetching the IPP attributes using ipptool..."
"${IPPTOOL}" -tv "${PRINTER_URL}" get-printer-attributes.test > "${IPPINFO_FILE}"

if [ $? -ne 0 ]; then
    echo "$0: Can't fetch IPP attributes, exiting..."
    exit 1
fi

if [ ! -s "${IPPINFO_FILE}" ]; then
    echo "ERROR: Fetched IPP info is empty..."
    exit 500
fi

PRINTER_NAME=`get_ippinfo_string "${IPPINFO_FILE}" "printer-name (nameWithoutLanguage) ="`
PRINTER_LOCATION=`get_ippinfo_string "${IPPINFO_FILE}" "printer-location (textWithoutLanguage) = "`

PRINTER_ICONS_STRING=`get_ippinfo_string "${IPPINFO_FILE}" "printer-icons (1setOf uri) ="`
PRINTER_ICONS=(${(s:,:)PRINTER_ICONS_STRING})

ICON_DIR="${TEMP_DIR}/icons"
IMAGESET_DIR="${ICON_DIR}/printer.iconset"
ICNS_TMP_FILE="${ICON_DIR}/printer.icns"

mkdir -p "${IMAGESET_DIR}"

for ICON_URL in $PRINTER_ICONS
do
    IMAGE_FILE_NAME=`basename $ICON_URL`
    
    echo "Downloading the printer image file ${IMAGE_FILE_NAME}..."
    
    if [ "$SECURE_MODE" = true ]; then
        curl -s -o "${ICON_DIR}/${IMAGE_FILE_NAME}" $ICON_URL
        CURL_RESULT=$?
    else
        curl -s -k -o "${ICON_DIR}/${IMAGE_FILE_NAME}" $ICON_URL
        CURL_RESULT=$?
    fi

    if [ $CURL_RESULT -ne 0 ]; then

        if [ $CURL_RESULT -eq 60 ]; then
            echo "Error downloading image ${IMAGE_FILE_NAME} due to missing trust info."
            echo "Please consider to not use the -s option if you are trusting the url"
            echo "${ICON_URL}"
        else
            echo "Error downloading image ${ICON_URL}."
        fi

    else
        IMAGE_RESOLUTION=`file "${ICON_DIR}/${IMAGE_FILE_NAME}" | awk -F "," '{print $2}' | tr -d ' '`
        
        echo "This image has the following dimensions: $IMAGE_RESOLUTION"    
        SIZE=`echo ${IMAGE_RESOLUTION} | awk -F "x" '{print $1}'`

        echo "Adding this image to the temporary macOS iconset..."
        case "$SIZE" in
            16)
                mv "${ICON_DIR}/${IMAGE_FILE_NAME}" "${IMAGESET_DIR}/icon_16x16.png"
                ;;
            32)
                mv "${ICON_DIR}/${IMAGE_FILE_NAME}" "${IMAGESET_DIR}/icon_16x16@2x.png"
                cp "${IMAGESET_DIR}/icon_16x16@2x.png" "${IMAGESET_DIR}/icon_32x32.png"
                ;;
            64)
                mv "${ICON_DIR}/${IMAGE_FILE_NAME}" "${IMAGESET_DIR}/icon_32x32@2x.png"
                cp "${IMAGESET_DIR}/icon_32x32@2x.png" "${IMAGESET_DIR}/icon_64x64.png"
                ;;
            128)
                mv "${ICON_DIR}/${IMAGE_FILE_NAME}" "${IMAGESET_DIR}/icon_64x64@2x.png"
                cp "${IMAGESET_DIR}/icon_64x64@2x.png" "${IMAGESET_DIR}/icon_128x128.png"
                ;;
            256)
                mv "${ICON_DIR}/${IMAGE_FILE_NAME}" "${IMAGESET_DIR}/icon_128x128@2x.png"
                cp "${IMAGESET_DIR}/icon_128x128@2x.png" "${IMAGESET_DIR}/icon_256x256.png"
                ;;
            512)
                mv "${ICON_DIR}/${IMAGE_FILE_NAME}" "${IMAGESET_DIR}/icon_256x256@2x.png"
                cp "${IMAGESET_DIR}/icon_256x256@2x.png" "${IMAGESET_DIR}/icon_512x512.png"
                ;;
            1024)
                mv "${ICON_DIR}/${IMAGE_FILE_NAME}" "${IMAGESET_DIR}/icon_512x512@2x.png"
                ;;
            *)
                echo "This image's dimensions do not fit into the needed iconset structure and will be skipped..."
        esac
    fi
done

ICON_FILE_COUNT=`ls -1 "${IMAGESET_DIR}"  | wc -l | tr -d " "`

if [ $ICON_FILE_COUNT -gt 0 ];
then
    echo "The iconset now contains $ICON_FILE_COUNT single images."

    echo "Creating an icns file from the fetched printer images..."
    iconutil -c icns -o "${ICNS_TMP_FILE}" "${IMAGESET_DIR}"

    echo "Saving the icns file to ${DEFAULT_ICON_PATH}..."
    cp "${ICNS_TMP_FILE}" "${DEFAULT_ICON_PATH}"

    if [ "${ICNS_COPY_DIR}" != "" ]; then
        echo "Saving a copy of the icns file to ${ICNS_COPY_DIR}/${OUTPUT_NAME}.icns..."
        cp "${ICNS_TMP_FILE}" "${ICNS_COPY_DIR}/${OUTPUT_NAME}.icns"
    fi
else
    echo "The iconset does not contain any image files, so we will skip all other icon handling..."
fi

echo "Saving the PPD to ${PPD_OUTPUT_DIR}/${OUTPUT_NAME}.ppd..."
cp "${PPD_FILE}" "${PPD_OUTPUT_DIR}/${OUTPUT_NAME}.ppd"

echo "Removing the temporary directory..."
rm -rf "${TEMP_DIR}"

exit 0