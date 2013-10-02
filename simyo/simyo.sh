#!/bin/bash
#
# quick-n-dirty simyo.es consumption checker v2
# (c) 2013 Pau Oliva - pof [at] eslack (.) org
#
# license: WTFPL (Do What The Fuck You Want To Public License)
# 
# api functions reverse engineered from the com.simyo android app

# enter your simyo.es username and password here:

USERNAME=""
PASSWORD=""

if [ -z "$USERNAME" ]; then
	echo "Edit the script to enter your username/password"
	exit 1
fi

INVOICELIST=0
INVOICEDOWNLOAD=0
VERBOSE=0
VAL=""
for opt in $* ; do
	case $opt in
		"-v") VERBOSE=1  ;;
		"-l") INVOICELIST=1  ;;
		"-b")
			VAL="billCycle"
			continue
		;;
		"-d")
			VAL="reqInvoiceId"
			INVOICEDOWNLOAD=1
			continue
		;;
		"-h")
			echo "Usage: $0 [-h|-v|-b num|-l|-d id]"
			echo "    -h     : show this help"
			echo "    -v     : verbose mode"
			echo "    -b num : bill cycle (from 1 to 6)"
			echo "    -l     : invoice list"
			echo "    -d id  : download invoice"
			exit 0
		;;
	esac
	case $VAL in
		"billCycle")
			billCycle=$opt
			VAL=""
		;;
		"reqInvoiceId")
			reqInvoiceId=$opt
			VAL=""
		;;
		*) VAL="" ;;
	esac
done

if [ $INVOICEDOWNLOAD -eq 1 ] && [ -z "$reqInvoiceId" ]; then
	echo "WARNING: Parameter -d requires an invoice id. Listing invoices instead."
	INVOICELIST=1
fi

if [ -z "$billCycle" ]; then
	billCycle=1
fi
if [ "$billCycle" -gt 6 ]; then
	echo "Billing Cylce must be an integer from 1 (current month) to 6"
	exit 1
fi

SIMYOPASS=$(php tripledes.php $PASSWORD 2>/dev/null)
kPublicKey="a654fb77dc654a17f65f979ba8794c34"

function getApiSig() {
	LOL=$(echo ${1} |tr [:upper:] [:lower:])
	LOL="f25a2s1m10${LOL}"
	php -r "error_reporting(0);\$s=hash_hmac('sha256', \"${LOL}\", 'f25a2s1m10', true); echo \$s;" |xxd -ps -c 100
}

function getJsonValue() {
	key="$1"
	file="$2"
	local J=$(cat $file)
	python -c "import json;print json.loads('$J')${key}" 2>/dev/null
	if [ $? != 0 ]; then
		key=$(echo $key |rev |cut -f 2 -d "'" |rev)
		cat $file |json_pp |grep "\"$key\"" |awk '{print $3}' |head -n 1 |cut -f 2 -d '"' |sed -e "s/,$//g"
		return 1
	fi
}

#### login
function api_login() {
	URL="https://www.simyo.es/api/login?publicKey=${kPublicKey}"
	apiSig=$(getApiSig $URL)
	URL="${URL}&apiSig=${apiSig}"
	curl -s -d "user=${USERNAME}&password=${SIMYOPASS}&apiSig=null" "${URL}" -o auth.json
	if [ $VERBOSE -eq 1 ]; then json_pp < auth.json ; fi

	sessionId=$(getJsonValue "['response']['sessionId']" auth.json)
	customerId=$(getJsonValue "['response']['customerId']" auth.json)

	if [ -z "$customerId" ]; then
		echo "Something went wrong."
		exit 1
	fi
}

#### subscriptions
function subscriptions() {
	URL="https://www.simyo.es/api/subscriptions/${customerId}?sessionId=${sessionId}&publicKey=${kPublicKey}" 
	apiSig=$(getApiSig $URL)
	URL="${URL}&apiSig=${apiSig}"
	curl -s "$URL" -o subscriptions.json
	if [ $VERBOSE -eq 1 ]; then json_pp < subscriptions.json ; fi

	registerDate=$(getJsonValue "['response']['subcriptions'][0]['registerDate']" subscriptions.json)
	mainProductId=$(getJsonValue "['response']['subcriptions'][0]['mainProductId']" subscriptions.json)
	billCycleType=$(getJsonValue "['response']['subcriptions'][0]['billCycleType']" subscriptions.json)
	msisdn=$(getJsonValue "['response']['subcriptions'][0]['msisdn']" subscriptions.json)
	subscriberId=$(getJsonValue "['response']['subcriptions'][0]['subscriberId']" subscriptions.json)
	payType=$(getJsonValue "['response']['subcriptions'][0]['payType']" subscriptions.json)
}

#### consumptionByCycle
function consumptionByCycle() {
	URL="https://www.simyo.es/api/consumptionByCycle/${customerId}?sessionId=${sessionId}&msisdn=${msisdn}&billCycleType=${billCycleType}&registerDate=${registerDate}&billCycle=${billCycle}&billCycleCount=${billCycleCount}&payType=${payType}&publicKey=${kPublicKey}"
	apiSig=$(getApiSig $URL)
	URL="${URL}&apiSig=${apiSig}"
	curl -s "$URL" -o consumptionByCicle.json
	if [ $VERBOSE -eq 1 ]; then json_pp < consumptionByCicle.json ; fi

	startDate=$(getJsonValue "['response']['consumptionsByCycle'][0]['startDate']" consumptionByCicle.json)
	startDate=$(echo $startDate |cut -c 1-10)
	endDate=$(getJsonValue "['response']['consumptionsByCycle'][0]['endDate']" consumptionByCicle.json)
	endDate=$(echo $endDate |cut -c 1-10)

	start=$(date -d@${startDate} "+%d/%m/%y")
	end=$(date -d@${endDate} "+%d/%m/%y")
	echo
	echo "Periodo de $start a $end"
	echo

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['voice']['count']" consumptionByCicle.json)
	chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['voice']['chargeTotal']" consumptionByCicle.json)
	hms=$(echo "obase=60;${count}" | bc |sed -e "s/^ //" -e "s/$/ /g" |rev |sed -e "s/ /s/" -e "s/ /m/" -e "s/ /h/" -e "s/ /d/" |rev |sed -e "s/d/d /" -e "s/h/h /" -e "s/m/m /")
	echo "Llamadas: ${hms} (${chargeTotal} EUR)"

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['sms']['count']" consumptionByCicle.json)
	chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['sms']['chargeTotal']" consumptionByCicle.json)
	echo "SMS: ${count} (${chargeTotal} EUR)"

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['mms']['count']" consumptionByCicle.json)
	if [ $count -gt 0 ]; then
		chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['mms']['chargeTotal']" consumptionByCicle.json)
		echo "MMS: ${count} (${chargeTotal} EUR)"
	fi

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['data']['count']" consumptionByCicle.json)
	chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['data']['chargeTotal']" consumptionByCicle.json)
	count=$(echo "scale=2; $count/1024/1024" |bc) # bytes to megabytes
	echo "Datos: ${count} MB (${chargeTotal} EUR)"

	PRINT=0

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['voicePremium']['count']" consumptionByCicle.json)
	if [ $count -gt 0 ]; then
		chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['voicePremium']['chargeTotal']" consumptionByCicle.json)
		hms=$(echo "obase=60;${count}" | bc |sed -e "s/^ //" -e "s/$/ /g" |rev |sed -e "s/ /s/" -e "s/ /m/" -e "s/ /h/" -e "s/ /d/" |rev |sed -e "s/d/d /" -e "s/h/h /" -e "s/m/m /")
		if [ $PRINT -eq 0 ]; then echo ; PRINT=1 ; fi
		echo "Llamadas Premium: ${hms} (${chargeTotal} EUR)"
	fi

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['smsPremium']['count']" consumptionByCicle.json)
	if [ $count -gt 0 ]; then
		chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['smsPremium']['chargeTotal']" consumptionByCicle.json)
		if [ $PRINT -eq 0 ]; then echo ; PRINT=1 ; fi
		echo "SMS Premium: ${count} (${chargeTotal} EUR)"
	fi

	PRINT=0

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['voiceOutgoingRoaming']['count']" consumptionByCicle.json)
	if [ $count -gt 0 ]; then
		chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['voiceOutgoingRoaming']['chargeTotal']" consumptionByCicle.json)
		hms=$(echo "obase=60;${count}" | bc |sed -e "s/^ //" -e "s/$/ /g" |rev |sed -e "s/ /s/" -e "s/ /m/" -e "s/ /h/" -e "s/ /d/" |rev |sed -e "s/d/d /" -e "s/h/h /" -e "s/m/m /")
		if [ $PRINT -eq 0 ]; then echo ; PRINT=1 ; fi
		echo "Llamadas Salientes Roaming: ${hms} (${chargeTotal} EUR)"
	fi

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['voiceIngoingRoaming']['count']" consumptionByCicle.json)
	if [ $count -gt 0 ]; then
		chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['voiceIngoingRoaming']['chargeTotal']" consumptionByCicle.json)
		hms=$(echo "obase=60;${count}" | bc |sed -e "s/^ //" -e "s/$/ /g" |rev |sed -e "s/ /s/" -e "s/ /m/" -e "s/ /h/" -e "s/ /d/" |rev |sed -e "s/d/d /" -e "s/h/h /" -e "s/m/m /")
		if [ $PRINT -eq 0 ]; then echo ; PRINT=1 ; fi
		echo "Llamadas Entrantes Roaming: ${hms} (${chargeTotal} EUR)"
	fi

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['smsRoaming']['count']" consumptionByCicle.json)
	if [ $count -gt 0 ]; then
		chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['smsRoaming']['chargeTotal']" consumptionByCicle.json)
		if [ $PRINT -eq 0 ]; then echo ; PRINT=1 ; fi
		echo "SMS Roaming: ${count} (${chargeTotal} EUR)"
	fi

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['mmsRoaming']['count']" consumptionByCicle.json)
	if [ $count -gt 0 ]; then
		chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['mmsRoaming']['chargeTotal']" consumptionByCicle.json)
		if [ $PRINT -eq 0 ]; then echo ; PRINT=1 ; fi
		echo "MMS Roaming: ${count} (${chargeTotal} EUR)"
	fi

	count=$(getJsonValue "['response']['consumptionsByCycle'][0]['dataRoaming']['count']" consumptionByCicle.json)
	if [ $count -gt 0 ]; then
		chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['dataRoaming']['chargeTotal']" consumptionByCicle.json)
		count=$(echo "scale=2; $count/1024/1024" |bc) # bytes to megabytes
		if [ $PRINT -eq 0 ]; then echo ; PRINT=1 ; fi
		echo "Datos Roaming: ${count} MB (${chargeTotal} EUR)"
	fi

	echo

	chargeTotal=$(getJsonValue "['response']['consumptionsByCycle'][0]['chargeTotal']" consumptionByCicle.json)
	echo "Consumo total: ${chargeTotal} EUR"
	echo
}

#### consumptionDetailDetailByCycle
function consumptionDetailDetailByCycle() {
	URL="https://www.simyo.es/api/consumptionDetailByCycle/${customerId}?msisdn=${msisdn}&sessionId=${sessionId}&billCycleType=${billCycleType}&billCycle=${billCycle}&registerDate=${registerDate}&billCycleCount=${billCycleCount}&payType=${payType}&publicKey=${kPublicKey}"
	apiSig=$(getApiSig $URL)
	URL="${URL}&apiSig=${apiSig}"
	curl -s "$URL" -o consumptionDetailByCicle.json
	if [ $VERBOSE -eq 1 ]; then json_pp < consumptionDetailByCicle.json ; fi
}


#### invoiceList
function invoiceList() {
	URL="https://www.simyo.es/api/invoiceList/${customerId}?msisdn=${msisdn}&sessionId=${sessionId}&billCycleType=${billCycleType}&registerDate=${registerDate}&publicKey=${kPublicKey}"
	apiSig=$(getApiSig $URL)
	URL="${URL}&apiSig=${apiSig}"
	curl -s "$URL" -o invoiceList.json
	if [ $VERBOSE -eq 1 ]; then json_pp < invoiceList.json ; fi

}

#### printInvoiceList
function printInvoiceList() {
	for i in `seq 0 6` ; do
		startDate=$(getJsonValue "['response']['invoiceList'][$i]['startDate']" invoiceList.json)
		if [ $? -eq 0 ]; then
			startDate=$(echo $startDate |cut -c 1-10)
			endDate=$(getJsonValue "['response']['invoiceList'][$i]['endDate']" invoiceList.json)
			endDate=$(echo $endDate |cut -c 1-10)
			invoiceNO=$(getJsonValue "['response']['invoiceList'][$i]['invoiceNO']" invoiceList.json)
			invoiceId=$(getJsonValue "['response']['invoiceList'][$i]['invoiceId']" invoiceList.json)
			start=$(date -d@${startDate} "+%d/%m/%y")
			end=$(date -d@${endDate} "+%d/%m/%y")
			echo "Factura $invoiceNO (id=$invoiceId) del $start al $end"
		fi
	done
}

#### downloadInvoice
function downloadInvoice() {
	invoiceList # we need invoiceList.json to find the invoiceNO
	invoiceNO=""
	for i in `seq 0 6` ; do
		invoiceId=$(getJsonValue "['response']['invoiceList'][$i]['invoiceId']" invoiceList.json)
		if [ $? -eq 0 ] && [ "$reqInvoiceId" = "$invoiceId" ] ; then
			invoiceNO=$(getJsonValue "['response']['invoiceList'][$i]['invoiceNO']" invoiceList.json)
			break
		fi
	done
	if [ -z "$invoiceNO" ]; then
		echo "Can't find invoice with id = $reqInvoiceId"
		exit 1
	fi

	URL="https://www.simyo.es/api/downloadInvoice?sessionId=${sessionId}&invoiceNO=${invoiceNO}&invoiceId=${invoiceId}&publicKey=${kPublicKey}"
	apiSig=$(getApiSig $URL)
	URL="${URL}&apiSig=${apiSig}"
	curl -s "$URL" -o downloadInvoice.json
	if [ $VERBOSE -eq 1 ]; then json_pp < downloadInvoice.json ; fi

	filename=$(getJsonValue "['response']['invoice']['filename']" downloadInvoice.json)
	if [ -n "$filename" ]; then
		echo "File: $filename"
		content=$(getJsonValue "['response']['invoice']['content']" downloadInvoice.json)
		echo $content |base64 -d > "./$filename"
	else
		echo "Oops... something went wrong downloading the invoice"
		exit 1
	fi

}

#### logout
function api_logout() {
	URL="https://www.simyo.es/api/logout?sessionId=${sessionId}&publicKey=${kPublicKey}"
	apiSig=$(getApiSig $URL)
	URL="${URL}&apiSig=${apiSig}"
	curl -s "$URL" -o logout.json
	if [ $VERBOSE -eq 1 ]; then json_pp < logout.json ; fi
}


api_login
subscriptions
if [ $INVOICELIST -eq 1 ]; then
	invoiceList
	printInvoiceList
	api_logout
	exit
fi
if [ -n "$reqInvoiceId" ]; then
	downloadInvoice
	api_logout
	exit
fi
# default:
consumptionByCycle
api_logout

#TODO
#consumptionDetailDetailByCycle

#### TODO:
#https://www.simyo.es/api/contact?publicKey=${kPublicKey}
#https://www.simyo.es/api/frequentNumbers/${customerId}?msisdn=${msisdn}&sessionId=${sessionId}&billCycleType=${billCycleType}&registerDate=${registerDate}&month=${month}&publicKey=${kPublicKey}
#https://www.simyo.es/api/messages/${customerId}?msisdn=${msisdn}&sessionId=${sessionId}&billCycleType=${billCycleType}&billCycle=${billCycle}&registerDate=${registerDate}&start=${start}&count=${count}&publicKey=${kPublicKey}
#https://www.simyo.es/api/mgmHistory/${customerId}?sessionId=${sessionId}&publicKey=${kPublicKey}
#https://www.simyo.es/api/rechargeHistory/${customerId}?msisdn=${msisdn}&sessionId=${sessionId}&billCycleType=${billCycleType}&registerDate=${registerDate}&startDate=${startDate}&endDate=${endDate}&publicKey=${kPublicKey}
#https://www.simyo.es/api/voiceCalls/${customerId}?msisdn=${msisdn}&sessionId=${sessionId}&billCycleType=${billCycleType}&billCycle=${billCycle}&registerDate=${registerDate}&start=${start}&count=${count}&publicKey=${kPublicKey}