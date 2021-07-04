#!/bin/sh
export JQ="jq --compact-output"; export CAT="$(which cat)";
export AWK="$(which awk)"; export SED="$(which sed)";
export GREP="$(which grep)"; export TAIL="$(which tail)";
export HEAD="$(which head)"; export DATE="$(which date)";
export CURL="$(which curl)"; export KILL="$(which kill)";
export KILLALL="$(which killall)"; export SLEEP="$(which sleep)";
export TELEGRAM_SEND="$(which telegram_send.sh)";
export URL="https://api.hh.ru/resumes"; export LOG="/var/log/hh.log";
export CODE="$(cat /var/log/hh.code)"; # код генерируется другим скриптом
export HEADERS="Authorization: Bearer $CODE";

PID_FILE='/tmp/hh.pid';
if [[ -e "$PID_FILE" ]]; then
    LAST_PID="$($CAT "$PID_FILE")";
    [[ "$LAST_PID" =~ ^[0-9]+$ ]] && $KILL -9 $LAST_PID;
fi
echo "$$" > "$PID_FILE";

function _update(){
    id="$1"; title="$2";
    RES_UPDATE="$($CURL --request POST -si -H "$HEADERS" "$URL/$id/publish")";
    if echo "$RES_UPDATE" | $GREP -Pq 'HTTP/2 20[0-9]'; then
        echo "Резюме \"$title\" успешно обновлено" >> "$LOG";
    elif echo "$RES_UPDATE" | $GREP -Pq 'HTTP/2 403'; then
        ERROR="Требуется авторизация";
        ERROR="$(echo "$ERROR" | $AWK '{print tolower($0)}')";
        # оповещение меня с помощью Telegram-бота
        $TELEGRAM_SEND "hh.sh: $ERROR" > /dev/null 2>&1;
        echo "$ERROR" >> "$LOG";
    else
        ERROR="$(echo "$RES_UPDATE" | $TAIL -n1 | $AWK -F\" '{print $10}')";
        echo "$ERROR - $title" >> "$LOG";
    fi
}

function weekend(){
    NOW_TIMESTAMP="$(date -d "$(date +"%D %X")" +%s)";
    NEXT_MONDAY_TIMESTAMP="$(date -d "08:00 next Monday" +%s)";
    $SLEEP "$(($NEXT_MONDAY_TIMESTAMP-$NOW_TIMESTAMP))";
}

function wait_until(){
    now="$(date +%s)"; until="$(date -d "$1" +%s)"; $SLEEP $(($until-$now));
}

function resume_list(){
    JQ_FILTER=".items[] | {id, title}, .access.type.name";
    EXCEPTION_RESUME="доступно только по прямой ссылке";
    EXCEPTION_RESUME="$EXCEPTION_RESUME|не видно никому";
    $CURL -s -H "$HEADERS" "$URL/mine" | $JQ "$JQ_FILTER" | 
                  $SED ':a;N;$!ba;s/}\n"/} "/g' | $GREP -Piv "$EXCEPTION_RESUME" | $AWK -F\" '{print $4","$8}';
}

while true; do
    n="0"; d="$(LANG='en_US' $DATE +%a)"; h="$($DATE +%k)";
    st="$($GREP -P '\d+:\d+:\d+' $LOG | $TAIL -n1 | $SED 's/.*[0-9]\+:[0-9]\+:0\?\([0-9]\+\).*/\1/')";
    if [[ "$d" == "Sun" ]] || [[ "$d" == "Sat" ]]; then weekend;
    elif [[ "$h" -lt "4" ]]; then wait_until "today 04:00:$st";
    elif [[ "$h" -lt "8" ]]; then wait_until "today 08:00:$ts";
    elif [[ "$h" -lt "12" ]]; then wait_until "today 12:00:$st";
    elif [[ "$h" -lt "16" ]]; then wait_until "today 16:00:$st";
    elif [[ "$h" -lt "20" ]]; then wait_until "today 20:00:$st";
    elif [[ "$h" -eq "20" ]]; then wait_until "tomorrow 08:00";
    fi
    resume_list | while read line; do
        id="$(echo "$line" | $AWK -F, '{print $1}')";
        title="$(echo "$line" | $AWK -F, '{print $2}')";
        if [[ "$n" == "0" ]]; then $DATE >> "$LOG"; n="1"; fi
        _update "$id" "$title";
    done
    echo >> "$LOG";
done
