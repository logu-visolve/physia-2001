spool create_db.log 

startup nomount pfile = $ORACLE_HOME/dbs/initSDEDBS02.ora
CREATE DATABASE "SDEDBS02"
   maxdatafiles 254
   maxinstances 8
   maxlogfiles 32
   character set US7ASCII
   national character set US7ASCII
DATAFILE '/u02/oradata/sdedbs02/system01.dbf' SIZE 175M
logfile '/u03/oradata/sdedbs02/redo01_a.log' SIZE 10M, 
    '/u03/oradata/sdedbs02/redo02_a.log' SIZE 10M,
    '/u03/oradata/sdedbs02/redo03_a.log' size 10M;

CREATE ROLLBACK SEGMENT r0 TABLESPACE SYSTEM
STORAGE (INITIAL 16K NEXT 16K MINEXTENTS 2 MAXEXTENTS 20);
ALTER ROLLBACK SEGMENT r0 ONLINE;

REM ************** TABLESPACE FOR ROLLBACK *****************
CREATE TABLESPACE RBS DATAFILE '/u04/oradata/sdedbs02/rbs01.dbf' SIZE 300M 
DEFAULT STORAGE ( INITIAL 1M NEXT 1M  MINEXTENTS 20 MAXEXTENTS 1024 PCTINCREASE 0);

REM ************** TABLESPACE FOR TEMPORARY *****************
CREATE TABLESPACE TEMP DATAFILE '/u05/oradata/sdedbs02/temp01.dbf' SIZE 300M 
DEFAULT STORAGE ( INITIAL 2M NEXT 2M MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0) TEMPORARY;

create tablespace USERS datafile '/u06/oradata/sdedbs02/ts_users.dbf'
size 10M default storage (pctincrease 0);

create tablespace TOOLS datafile '/u06/oradata/sdedbs02/ts_tools.dbf'
size 10M default storage (pctincrease 0);

REM **** Creating four rollback segments ****************
CREATE ROLLBACK SEGMENT r01 TABLESPACE RBS;
CREATE ROLLBACK SEGMENT r02 TABLESPACE RBS;
CREATE ROLLBACK SEGMENT r03 TABLESPACE RBS;
CREATE ROLLBACK SEGMENT r04 TABLESPACE RBS;
ALTER ROLLBACK SEGMENT r01 ONLINE;
ALTER ROLLBACK SEGMENT r02 ONLINE;
ALTER ROLLBACK SEGMENT r03 ONLINE;
ALTER ROLLBACK SEGMENT r04 ONLINE;
ALTER ROLLBACK SEGMENT r0 OFFLINE;

DROP ROLLBACK SEGMENT r0;

REM **** SYS and SYSTEM users ****************
alter user sys temporary tablespace TEMP;
alter user system default tablespace TOOLS temporary tablespace TEMP;


@$ORACLE_HOME/rdbms/admin/catalog.sql
@$ORACLE_HOME/rdbms/admin/catproc.sql
@$ORACLE_HOME/rdbms/admin/catblock.sql
@$ORACLE_HOME/rdbms/admin/caths.sql
@$ORACLE_HOME/rdbms/admin/otrcsvr.sql
@$ORACLE_HOME/rdbms/admin/utlsampl.sql

connect system/manager
@$ORACLE_HOME/sqlplus/admin/pupbld.sql

spool off




