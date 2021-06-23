#!/bin/sh

n="0";
JQ="jq --compact-output";
CURL="$(which curl)";
SED="$(which sed)";
GREP="$(which grep)";
AWK="$(which awk)";
DATE="$(which date)";
HEAD="$(which head)";
TAIL="$(which tail)";
TELEGRAM_SEND="$(which telegram_send.sh)";
LOG_FILE="/var/log/hh.log";
HH_CODE="$(cat /var/log/hh.code)"; # Код генерирует другой скрипт
URL="https://api.hh.ru/resumes";

$CURL -s -H "Authorization: Bearer $HH_CODE" "$URL/mine" |
    $JQ ".items[] | {id, title}, .access.type.name" | 
    $SED ':a;N;$!ba;s/}\n"/} "/g' |
    $GREP -Piv 'доступно только по прямой ссылке|не видно никому' |
    $AWK -F\" '{print $4","$8}' | while read line; do
        id="$(echo "$line" | $AWK -F, '{print $1}')";
        title="$(echo "$line" | $AWK -F, '{print $2}')";
        NOW="$($DATE +%s)";
        RESUME="$($CURL --request GET -s -H "Authorization: Bearer $HH_CODE" \
                                           "$URL/$id")";
        UPDATED_AT="$(echo "$RESUME" | $JQ '.updated_at' | $SED 's/\"//g')";
        UPDATED_AT_TIMESTAMP="$($DATE -d "$UPDATED_AT" +"%s")";
        DIFF_TIME_UPTADED_AT="$((($NOW-$UPDATED_AT_TIMESTAMP)))";
        WAIT_TIME="$((14400-$DIFF_TIME_UPTADED_AT))";
        # Обновит резюме если прошло больше 4 часов с последнего обновления
        if [[ "$WAIT_TIME" -le "0" ]]; then
            if [[ "$n" == "0" ]]; then
                $DATE > "$LOG_FILE"; n="1";
            else
                $DATE >> "$LOG_FILE";
            fi
            id="$(echo "$line" | $AWK -F, '{print $1}')";
            title="$(echo "$line" | $AWK -F, '{print $2}')";
            UPDATE="$($CURL --request POST -si -H "Authorization: Bearer $HH_CODE" \
                                                  "$URL/$id/publish")";
            if echo "$UPDATE" | $GREP -Pq 'HTTP/2 20[0-9]'; then
                echo "Резюме $title успешно обновлено" >> "$LOG_FILE";
            elif echo "$UPDATE" | $GREP -Pq 'HTTP/2 403'; then
                ERROR="Требуется авторизация";
                ERROR_LOWER="$(echo "$ERROR" | $AWK '{print tolower($0)}')";
                # Оповещение меня с помощью Telegram-бота
                $TELEGRAM_SEND "hh.sh: $ERROR_LOWER" > /dev/null 2>&1;
                echo "$ERROR" >> "$LOG_FILE";
                break;
            else
                echo "$UPDATE" | $GREP -P '^HTTP\/2' | $HEAD -c-2 >> "$LOG_FILE";
                echo "- $UPDATE" | $TAIL -n1 | $AWK -F\" '{print $4}' >> "$LOG_FILE";
            fi
        fi
    done
