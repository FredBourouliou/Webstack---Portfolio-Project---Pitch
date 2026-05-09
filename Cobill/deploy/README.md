# Déploiement

Cible : Ubuntu 22.04 LTS, AWS EC2 t3.micro, eu-west-3 (Paris). N'importe quel autre VPS Linux fait l'affaire.

## 1. Provisionner la machine

Console AWS ou CLI, peu importe. L'objectif : une instance Ubuntu 22.04 avec une IP publique et un security group qui ouvre 22, 80, 443.

```bash
aws ec2 run-instances \
    --region eu-west-3 \
    --image-id ami-0bcaa9c7e3c79f2a4 \
    --instance-type t3.micro \
    --key-name your-keypair \
    --security-groups your-sg-allowing-22-80-443 \
    --associate-public-ip-address \
    --tag-specifications \
        'ResourceType=instance,Tags=[{Key=Name,Value=cobill}]'
```

L'`ami-id` ci-dessus est valable pour eu-west-3 au moment de l'écriture, à actualiser via <https://cloud-images.ubuntu.com/locator/ec2/>.

Pointer le record DNS A vers l'IP publique de l'instance avant de lancer certbot.

## 2. Bootstrap

```bash
scp -r deploy ubuntu@<host>:/tmp/cobill-deploy
ssh ubuntu@<host> 'sudo bash /tmp/cobill-deploy/setup-server.sh'
```

Le script est idempotent. Ce qu'il fait :

| Étape | Effet |
|---|---|
| `apt install` | gnucobol, ghostscript, apache2, certbot, curl, jq, ufw, rsync, make |
| `a2enmod` | cgi, headers, rewrite, ssl, mpm_prefork |
| user `cobill` | utilisateur système, propriétaire de `/opt/cobill` |
| layout | `/opt/cobill/{bin,data,pdf,lib,web,src/postscript}` |
| symlinks | `bin/{data,pdf,src,lib}` vers les siblings (résolution des chemins relatifs COBOL) |
| `cobill.conf` | vhost Apache, mod_cgi, headers de sécurité |
| `ufw` | 22, 80, 443 |
| `/etc/cobill/cobill.env` | hash sha512crypt du password admin |
| `/etc/apache2/envvars` | source l'env file pour que `PassEnv` fonctionne |

Le script affiche une seule fois le password admin en clair — à sauvegarder immédiatement. Seul le hash est persisté.

## 3. Pousser le code

```bash
# depuis le dossier Cobill/
scripts/deploy.sh ubuntu@<host>
```

`deploy.sh` rsync les sources (sans `bin/`, `data/`, `pdf/`), puis lance `make build` sur le serveur. Les binaires sont du Linux ELF, donc compilés sur place.

## 4. Certificat TLS

Une fois le DNS propagé :

```bash
ssh ubuntu@<host> 'sudo certbot --apache -d cobill.your-domain.tld'
```

Certbot écrit `cobill-le-ssl.conf` (vhost :443) et programme le renouvellement via systemd timer.

## 5. Vérifier

```bash
curl -sS -i https://cobill.your-domain.tld/login.html | head -3
curl -sS -i https://cobill.your-domain.tld/cgi-bin/client?action=list | head -3
# attendu : 302 Location: /login.html
```

## 6. Redéployer après modif

```bash
scripts/deploy.sh ubuntu@<host>
```

Rebuild les binaires sur la cible, reload Apache. Les sessions actives survivent au reload.

## 7. Backup

Sauvegarder `/opt/cobill/data/`. Cron tar quotidien :

```bash
0 3 * * * tar -czf /home/ubuntu/backups/cobill-$(date +\%Y\%m\%d).tar.gz \
    -C /opt/cobill data
```

Push S3/Glacier en aval si besoin.

---

## Hardening en place

- Apache mpm_prefork (adapté CGI fork-per-request)
- Headers : `X-Content-Type-Options nosniff`, `X-Frame-Options DENY`, `Referrer-Policy strict-origin-when-cross-origin`, `Strict-Transport-Security` sous HTTPS
- `<Directory>` deny sur `/opt/cobill/data` et `/opt/cobill/src`
- `<FilesMatch>` deny sur `*.dat`, `*.idx`, `*.cob`, `*.cpy`, `*.ps`
- Cookies `HttpOnly` + `SameSite=Lax`
- UFW limité à 22 / 80 / 443
- Password admin sha512crypt via libc `crypt(3)` (`COBILL_AUTH_HASH`), jamais stocké en clair

## À faire (post-pitch)

- Comptes multi-utilisateur (un seul `admin` actuellement)
- Rate limit sur `/cgi-bin/auth?action=login` (mod_evasive ou fail2ban)
- Backup off-host (S3 + Glacier)
- Centralisation des logs (CloudWatch ou Loki)
