-- Read-only user for the database agent (db-query). Run it once in EACH environment
-- (local, dev, pre, prod) as an administrator, with a different password in each one.
-- Generate each password with: openssl rand -base64 24
--
-- Replace:
--   <db>        the application's database
--   <password>  this environment's password (it goes to .claude/db.<env>.env, never to git)
--   '%'         if you can, the host the connections arrive from. Through an SSH tunnel that
--               is the host the tunnel ends on (the bastion's IP, or 'localhost' if the tunnel
--               ends on the database server itself).
--
-- db-query refuses the user if it has anything beyond SELECT / SHOW VIEW, or a role.

CREATE USER 'claude_ro'@'%'
  IDENTIFIED BY '<password>'
  WITH MAX_USER_CONNECTIONS 2;

GRANT SELECT, SHOW VIEW ON `<db>`.* TO 'claude_ro'@'%';

-- Check: it must show only USAGE and SELECT, SHOW VIEW on <db>.
SHOW GRANTS FOR 'claude_ro'@'%';

-- To remove it:
-- DROP USER 'claude_ro'@'%';
