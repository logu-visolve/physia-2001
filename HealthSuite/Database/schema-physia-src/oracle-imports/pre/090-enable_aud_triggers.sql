create or replace procedure enable_aud_triggers
                                     is 
                                     
       	v_trig_name user_triggers.trigger_name%type;
       	v_sql_stmt varchar2(200);
	
  	
        cursor c_trig_name is select trigger_name from user_triggers where trigger_name like '%AUD%';
		
begin

	open c_trig_name;
	
	loop
		fetch c_trig_name into v_trig_name;
		
		exit when c_trig_name%notfound;
		
		v_sql_stmt := 'alter trigger '||v_trig_name||' enable';

		execute immediate v_sql_stmt;
		
	end loop;
	
end;
/
show errors;
