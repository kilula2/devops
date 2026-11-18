#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK]  $desc"
        ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
check "Порт SSH нестандартный" "no" "$(sudo sshd -T | awk '/^port/{print ($2=="22"?"yes":"no")}')"
check "MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика incoming = deny" "deny" "$(sudo ufw status verbose | grep 'Default:' | awk -F, '{print $1}' | awk '{print $NF}')"

echo "[3] Учётные записи"
awk -F: ' $3>=1000 && $3<65534 {printf " %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер Nginx"
check "Nginx активен" "active" "$(systemctl is-active nginx)"
check "Сайт доступен по HTTPS" "200" "$(curl -k -s -o /dev/null -w "%{http_code}" https://devops.local/)"

echo "[5] Контейнеризация"
check "Служба Docker активна" "active" "$(systemctl is-active docker)"
check "СУБД в состоянии healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo 'not found')"
check "Порты 5000/5432 изолированы" "0" "$(ss -tln | grep -E ':(5000|5432)' | grep -v '127.0.0.1' | wc -l)"
check "Права .env (600)" "600" "$(stat -c '%a' ~/devops/app/.env 2>/dev/null || echo 'no file')"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1