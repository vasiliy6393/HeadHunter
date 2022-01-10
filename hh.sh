#!/bin/sh
#  AUTHOR: Vasiliy Pogoreliy, vasiliy@pogoreliy.ru 

# Утилита выводит результат работы в <stdout>
# До этого сам скрипт писал в лог, но в процессе эксплуатации мне это показалось неудобным
# Каждая строчка в скрипте хорошо продумана и приното взвешенное решение почему сделано так, а не иначе
# У Вас может быть другое представление о том как должно быть - переделайте под себя

# Комментариев в скрипте почти нет и не думаю что они так сильно нужны, bash простой язык,
# комментарии нужны разве что к регуляркам

# PATH="your_path:$PATH"

export USER="$1";
export CMD="$2";
if [[ "_$USER" == "_%admin% ]]; then
    CLIENT_ID="$CLIENT_ID";
    CLIENT_SECR="$CLIENT_SECRET";
elif [[ "_$USER" == "_%other_user%" ]]; then
    CLIENT_ID="$CLIENT_ID";
else
    echo "Пользователь не найден!";
    exit;
fi

export CP="$(which cp)";
export PS="$(which ps)";
export JQ="jq --compact-output"; export CAT="$(which cat)";
export AWK="$(which awk)"; export SED="$(which sed)";
export GREP="$(which grep)"; export DATE="$(which date)";
export HEAD="$(which head)"; export TAIL="$(which tail)";
export CURL="$(which curl)"; export SLEEP="$(which sleep)";
export KILL="$(which kill)"; export TELEGRAM_SEND="$(which telegram_send.sh)";
export URL="https://api.hh.ru/resumes"; export LOG="/var/log/hh/hh_$USER.log";

echo "Started: \$DATE=$($DATE +"%d.%m.%Y | %H:%M:%S"); \$PID=$$;";
PID_FILE="/tmp/hh_$USER.pid";
if [[ -e "$PID_FILE" ]]; then
    LAST_PID="$($CAT "$PID_FILE")";
    if [[ "$LAST_PID" =~ ^[0-9]+$ ]]; then
        $KILL $LAST_PID;
    fi
fi
echo "$$" > "$PID_FILE";

function main(){
    n="$1";
    resume_list | $GREP -Pv 'first_name' | while read line; do
        id="$(echo "$line" | $AWK -F, '{print $1}')";
        title="$(echo "$line" | $AWK -F, '{print $2}')";
        if [[ "$n" == "0" ]]; then $DATE; n="1"; fi
        _update "$id" "$title";
    done
    echo;
}

function _update(){
    id="$1";
    title="$2";
    TIME="$($DATE | $GREP -Po '\d+:\d+:\d+')";
    HTTP_STATUS_CODE_200="Резюме \"$title\" успешно обновлено";
    HTTP_STATUS_CODE_429="Резюме \"$title\": touch_limit_exceeded";
    HTTP_STATUS_CODE_403="Требуется авторизация";
    CODE="$(cat /var/log/hh/hh_$USER.code)";
    HEADERS="Authorization: Bearer $CODE";

    RES_UPDATE="$($CURL --request POST -si -H "$HEADERS" "$URL/$id/publish")";
    if echo "$RES_UPDATE" | $GREP -Pq 'HTTP/2 20[0-9]'; then
        echo "$TIME: $HTTP_STATUS_CODE_200";
    elif echo "$RES_UPDATE" | $GREP -Pq 'HTTP/2 429'; then
        echo "$TIME: $HTTP_STATUS_CODE_429";
    elif echo "$RES_UPDATE" | $GREP -Pq 'HTTP/2 403'; then
        ERROR="$HTTP_STATUS_CODE_403";
        ERROR_LOWER="$(echo "$HTTP_STATUS_CODE_403" | $AWK '{print tolower($0)}')";
        # оповещение меня с помощью Telegram-бота
        $TELEGRAM_SEND "hh_$USER.sh: $TIME | $ERROR_LOWER";
        echo "$TIME: $ERROR";
        /bin/hh_$USER.sh "$USER" "$CMD";
        main "$n";
    else
        ERROR="$(echo "$RES_UPDATE" | $TAIL -n1 | $AWK -F\" '{print $10}')";
        echo "$TIME: $ERROR - $title";
    fi
}

function weekend(){
    NOW_TIMESTAMP="$(date -d "$(date +"%D %X")" +%s)";
    NEXT_MONDAY_TIMESTAMP="$(date -d "08:00 next Monday" +%s)";
    $SLEEP "$(($NEXT_MONDAY_TIMESTAMP-$NOW_TIMESTAMP))";
}

function wait_until(){
    now="$(date +%s)"; until="$(date -d "$1" +%s)";
    $SLEEP $(($until-$now));
}

function resume_list(){
    CODE="$(cat /var/log/hh/hh_$USER.code)";
    HEADERS="Authorization: Bearer $CODE";
    JQ_FILTER=".items[] | {id, title}, .access.type.name";
    EXCEPTION_RESUME="доступно только по прямой ссылке";
    EXCEPTION_RESUME="$EXCEPTION_RESUME|не видно никому";
    RES="$($CURL -s -H "$HEADERS" "$URL/mine")";
    if echo "$RES" | $GREP -Pq 'bad_authorization|bad-auth-type'; then
        auth;
        echo "$RES"
    else
        echo "$RES"
        echo "$RES" | $GREP -P '^{' | $JQ "$JQ_FILTER" | 
                    $SED ':a;N;$!ba;s/}\n"/} "/g' | $GREP -Piv "$EXCEPTION_RESUME" |
                    $AWK -F\" '{print $4","$8}';
    fi
}

function auth(){
    /my_bin/hh.sh "%admin% "auth";
}

if [[ "a$CMD" == "acode" ]]; then
    UPDATE_NOW="$3";
    st=0;
    while true; do
        n="0"; d="$(LANG='en_US' $DATE +%a)"; h="$($DATE +%k)";
        if [[ "$UPDATE_NOW" == "now" ]]; then UPDATE_NOW="NULL";
        elif [[ "$d" == "Sun" ]] || [[ "$d" == "Sat" ]]; then weekend;
        elif [[ "$h" -lt "4" ]]; then auth; wait_until "today 04:00:00";
        elif [[ "$h" -lt "8" ]]; then wait_until "today 08:00:00";
        elif [[ "$h" -lt "12" ]]; then wait_until "today 12:00:00";
        elif [[ "$h" -lt "16" ]]; then wait_until "today 16:00:00";
        elif [[ "$h" -lt "20" ]]; then wait_until "today 20:00:00";
        elif [[ "$h" -eq "20" ]]; then st=0; wait_until "tomorrow 08:00:00";
        fi
        st=$(($st+1));
        $SLEEP $st;
        echo "update";
        main "$n";
    done
elif [[ "a$CMD" == "aauth" ]]; then
    # Не нашёл другого решения авторизации по протоколу oauth
    # Пошёл по самому простому для себя пути
    # Не лучшее решение, но работает =)
    # В будущем возможно заморочусь и разберусь как авторизовываться по-нормальному
    echo -en "start: ";
    URL_PARAMS="?response_type=code&client_id=$CLIENT_ID";
    URL="https://ekaterinburg.hh.ru/oauth/authorize$URL_PARAMS";
    firefox "$URL" &
    mouse_location="$(xdotool getmouselocation | tr ' ' '\n')";
    mouse_location_x="$($GREP -P 'x' <<< $mouse_location | $AWK -F: '{print $2}')";
    mouse_location_y="$($GREP -P 'y' <<< $mouse_location | $AWK -F: '{print $2}')";
    $SLEEP 5;
    xdotool mousemove 515 400;
    xdotool click 1;
    xdotool mousemove $mouse_location_x $mouse_location_y;
    echo "true";
    sleep 5;
    CODE="$(cat /var/log/hh/hh_$USER.code)";
    curl -s -F grant_type=authorization_code \
            -F client_id=$CLIENT_ID \
            -F client_secret=$CLIENT_SECR \
            -F code=$CODE "https://hh.ru/oauth/token" |
        cut -d "\"" -f "4" > "/var/log/hh/hh_$USER.code";
    sleep 3;
    xdotool key Ctrl+w;
fi
