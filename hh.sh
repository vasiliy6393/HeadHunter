#!/bin/sh

export JQ="jq --compact-output";
export CAT="$(which cat)";
export AWK="$(which awk)";
export SED="$(which sed)";
export GREP="$(which grep)";
export TAIL="$(which tail)";
export HEAD="$(which head)";
export DATE="$(which date)";
export CURL="$(which curl)";
export KILL="$(which kill)";
export KILLALL="$(which killall)";
export SLEEP="$(which sleep)";
export TELEGRAM_SEND="$(which telegram_send.sh)";
export URL="https://api.hh.ru/resumes";
export CODE="$(cat /var/log/hh.code)"; # код генерируется другим скриптом
export LOG="/var/log/hh.log";

PID_FILE='/tmp/hh.pid';
if [[ -e "$PID_FILE" ]]; then
    LAST_PID="$($CAT "$PID_FILE")";
    [[ "$LAST_PID" =~ ^[0-9]+$ ]] && $KILL -9 $LAST_PID;
fi
echo "$$" > "$PID_FILE";

function _update(){
    id="$1";
    title="$2";
    RES_UPDATE="$($CURL --request POST -si -H "Authorization: Bearer $CODE" \
                                          "$URL/$id/publish")";
    if echo "$RES_UPDATE" | $GREP -Pq 'HTTP/2 20[0-9]'; then
        echo "Резюме \"$title\" успешно обновлено" >> "$LOG";
    elif echo "$RES_UPDATE" | $GREP -Pq 'HTTP/2 403'; then
        ERROR="Требуется авторизация";
        ERROR_LOWER="$(echo "$ERROR" | $AWK '{print tolower($0)}')";
        # оповещение меня с помощью Telegram-бота
        $TELEGRAM_SEND "hh.sh: $ERROR_LOWER" > /dev/null 2>&1;
        echo "$ERROR" >> "$LOG";
    else
        ERROR="$(echo "$RES_UPDATE" | $TAIL -n1 | $AWK -F\" '{print $10}')";
        echo "$ERROR - $title" >> "$LOG";
    fi
}

h="$(date +%k)"; m="$(date +%M | $SED 's/^0//')";
s="$(date +%S | $SED 's/^0//')";
st="$($GREP -P '\d+:\d+:\d+' $LOG | $TAIL -n1 |
      $SED 's/.*[0-9]\+:[0-9]\+:\([0-9]\+\).*/\1/' | $SED 's/^0//')";
if [[ "$h" -lt "4" ]]; then WAIT="$((14400-($h*3600+$m*60+$s)+$st))";
elif [[ "$h" -lt "8" ]]; then WAIT="$((28800-($h*3600+$m*60+$s)+$st))";
elif [[ "$h" -lt "12" ]]; then WAIT="$((43200-($h*3600+$m*60+$s)+$st))";
elif [[ "$h" -lt "16" ]]; then WAIT="$((57600-($h*3600+$m*60+$s)+$st))";
elif [[ "$h" -lt "20" ]]; then WAIT="$((72000-($h*3600+$m*60+$s)+$st))";
elif [[ "$h" -eq "20" ]]; then WAIT="$((28800+86400-($h*3600+$m*60+$s)))";
fi
$SLEEP $WAIT
while true; do
    n="0";
    $CURL -s -H "Authorization: Bearer $CODE" "$URL/mine" |
        $JQ ".items[] | {id, title}, .access.type.name" | 
        $SED ':a;N;$!ba;s/}\n"/} "/g' |
        $GREP -Piv 'доступно только по прямой ссылке|не видно никому' |
        $AWK -F\" '{print $4","$8}' | while read line; do
            id="$(echo "$line" | $AWK -F, '{print $1}')";
            title="$(echo "$line" | $AWK -F, '{print $2}')";
            if [[ "$n" == "0" ]]; then $DATE >> "$LOG"; n="1"; fi
            _update "$id" "$title";
        done
        echo >> "$LOG";
    h="$(date +%k)"; m="$(date +%M)"; s="$(date +%S)";
    if [[ "$h" -eq "20" ]]; then
        $SLEEP $((14400+86400-($h*3600+$m*60+$s)));
    else
        $SLEEP 4h;
    fi
done
