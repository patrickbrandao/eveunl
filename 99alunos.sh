#!/bin/sh

#
# Script para criar 99 alunos
# senha => 123456
# Forma de usar:
#   sh 99alunos.sh > alunos.sql
#   mysql -peve-ng -u root eve_ng_db < alunos.sql

role=admin
prefix=aluno
domain=ajustefino.com
limite=99
senha=8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92

for uid in $(seq 1 1 $limite); do
    nuid="0$uid"
    [ "$uid" -ge 10 ] && nuid=$uid
    username="$prefix$nuid"
    showname="Aluno $nuid"
    email="$name@$domain"
    SQL="INSERT INTO users (username, cookie, email, expiration, name, password, session, ip, role, folder, html5) VALUES ('$username',NULL,'$email',-1,'$showname','$senha',NULL,NULL,'$role',NULL,NULL);"
    echo "$SQL"
done
