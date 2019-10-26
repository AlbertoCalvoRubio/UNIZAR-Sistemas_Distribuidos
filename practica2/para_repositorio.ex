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
# orc: oustanding reply count
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
end

def
 