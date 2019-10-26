# AUTOR: Oscar Baselga y Alberto Calvo
 # FICHERO: para_repositorio.ex
 # FECHA: 26 de octubre de 2019
 # TIEMPO: 
 # DESCRIPCION:

defmodule Para_Repositorio do
 def lector(pidRepo, op_lectura) do
    pre_protocol()
    send(pidRepo, {op_lectura, self()})
    receive do
        {:reply, texto} -> texto
    end
    post_protocol()
 end

 def escritor(pidRepo, op_escritura) do
    pre_protocol()
    send(pidRepo, {op_escritura, self(), texto})
    receive do
        {:reply, :ok} -> IO.puts("Fin escritura")
    end
    post_protocol()
 end

# me: identificador entre los n procesos
# n: total de procesos lectores o escritores
# osn: our_sequence_number
# hsn: highest_sequence_number
# orc: oustanding_reply_count
 defp global_vars(me, n, osn, hsn, orp) do
    {n_osn, n_hsn, n_orp} = receive do
        {:read, :me, pid} -> send(pid, me); {osn, hsn,orp}
        {:read, :n, pid} -> send(pid, n); {osn, hsn,orp}
        {:read, :osn, pid} -> send(pid, osn); {osn, hsn,orp}
        {:read, :hsn, pid} -> send(pid, hsn); {osn, hsn,orp}
        {:read, :orp, pid} -> send(pid, orp); {osn, hsn,orp}
        {:write, :osn, pid, value} -> send(pid, :ok); {value, hsn, orp}
        {:write, :hsn, pid, value} -> send(pid, :ok); {osn, value, orp}
        {:write, :orp, pid, value} -> send(pid, :ok); {osn, hsn, value}
    end
    global_vars(me, n, n_osn, n_hsn, n_orp)   
 end

 def wait_acks(number) when number > 0 do
    receive do
        {:ack}
    end
    wait_acks(number-1)
 end

 #def send_acks(pid_global_vars) do
    # sacamos los actores que esperan nuestra confirmacion
 #   send(pid_global_vars,{:read,:pid_actors_queue,self()})
 #   pid_actors_queue = receive do
 #       {pid_actors_queue} -> pid_actors_queue
 #   end
    # enviamos la confirmacion a todos esos actores
 #   Enum.each(pid, fn x -> send(x,:ack) end)
    # vaciamos toda la cola de actores esperando
 #   send(pid_global_vars,{:write,:pid_actors_queue,self(),[]})
 #   receive do
 #       {:ok}
 #   end
 #end

 def begin_op(pid_global_vars,pid_actors,op_type) do
    # modificamos el estado del proceso
    send(pid_global_vars,{:write,:state,self(),:trying})
    receive do
        {:ok}
    end
    # incrementamos nuestro reloj
    send(pid_global_vars,{:read,:clock,self()})
    clock = receive do
        {clk} -> send(pid_global_vars,{:write,:clock,self(),clk+1}); clk+1
    end
    receive do
        {:ok}
    end
    # ----------------------------------- MODIFICAR CON FUNCION REQUEST
    # enviamos las peticiones al resto de actores (incluir la matriz booleana)
    send(pid_global_vars,{:read,:n,self()})
    n = receive do
        {n} -> n
    end
    spawn(fn -> send_request(pid_actors,clock,n-1,op_type) end) # con spawn para no secuencializar los envios
    # -----------------------------------
    # esperamos a que nos confirmen todos
    wait_acks(n-1) # n para saber cuantos tiene que esperar
    # modificamos el estado del proceso
    send(pid_global_vars,{:write,:state,self(),:in})
    receive do
        {:ok}
    end
 end

 def end_op(pid_global_vars) do
    # modificamos el estado del proceso
    send(pid_global_vars,{:write,:state,self(),:out})
    receive do
        {:ok}
    end
    # enviamos confirmacion a los actores que esperaban
    permission(pid_global_vars)
 end

 def permission(j) do

 end

 def request(k,j,op_t) do

 end

end
 