# AUTOR: Oscar Baselga y Alberto Calvo
 # FICHERO: para_repositorio.ex
 # FECHA: 26 de octubre de 2019
 # TIEMPO: 
 # DESCRIPCION:

defmodule Para_Repositorio do
 def lector(pidRepo, me, listaVecinos, op_lectura) do
    IO.puts("Inicio lector")
    n = length(listaVecinos)
    {:ok, globalvars} = GlobalVars.start_link()
    semaforo = Semaforo.create()
    spawn(fn -> recibir_peticion(globalvars, semaforo, me, op_lectura) end)
    pre_protocol(globalvars, semaforo, listaVecinos, n, me, op_lectura)
    osn = GlobalVars.get(globalvars, :osn)
    # ---- Inicio SC ----
    send(pidRepo, {op_lectura, self()})
    receive do
        {:reply, texto} -> IO.puts("Lector #{me}: #{osn} --> #{texto}")
    end
    # ----- Fin SC ------
    post_protocol(globalvars)
 end

 def escritor(pidRepo, me, listaVecinos, op_escritura, texto) do
    IO.puts("Inicio escritor")
    n = length(listaVecinos)
    globalvars = GlobalVars.start_link()
    IO.inspect(globalvars)
    semaforo = Semaforo.create()
    IO.inspect(semaforo)
    spawn(fn -> recibir_peticion(globalvars, semaforo, me, op_escritura) end)
    pre_protocol(globalvars, semaforo, listaVecinos, n, me, op_escritura)
    osn = GlobalVars.get(globalvars, :osn)
    # ---- Inicio SC ----
    send(pidRepo, {op_escritura, self(), texto})
    receive do
        {:reply, :ok} -> IO.puts("Escritor #{me}: #{osn} --> #{texto}")
    end
    # ----- Fin SC ------
    post_protocol(globalvars)
 end
 
 defp pre_protocol(globalvars, semaforo, listaVecinos, n, me, op_t) do
    IO.puts("Inicio pre_protocol")
    pid = self()
    Semaforo.wait(semaforo, pid)
    # ---- Exclusión mútua ----
    GlobalVars.set(globalvars, :request_SC, :true)  # request_SC = true
    osn = GlobalVars.get(globalvars, :hsn) + 1
    GlobalVars.set(globalvars, :osn, osn)
    # ---- Fin exclusión mútua ----
    Semaforo.signal(semaforo)
    spawn(fn -> recibir_reply(pid, n) end) # Se escucha las respuestas de los demas procesos
    Enum.each(listaVecinos, fn pidVecino -> send(pidVecino, {:request_SC, osn, me, op_t}) end) # Enviar peticiones
    receive do  # Esperar al permiso para entrar en SC
        :ok_SC -> :ok
    end
    IO.puts("Fin pre_protocol")
 end

 defp post_protocol(globalvars) do
    IO.puts("Inicio post_protocol")
    GlobalVars.set(globalvars, :request_SC, :false)  # request_SC = false
    listaAplazados = GlobalVars.get(globalvars, :listaAplazados)
    Enum.each(listaAplazados, fn aplazado -> send(aplazado, :reply_SC) end) # Contestar a cada proceso
    GlobalVars.set(globalvars, :globalvars, []) # Vaciar lista de aplazados, ya se han contestado 
    IO.puts("Fin post_protocol") 
 end

 defp recibir_peticion(globalvars, semaforo, me, op1) do
    {pidVecino, osnVecino, idVecino, op2} = receive do
        {:request_SC, n_pid, n_osn, n_id, n_op2} -> {n_pid, n_osn, n_id, n_op2}
    end
    GlobalVars.set(globalvars, :hsn, max(GlobalVars.get(globalvars, :hsn), osnVecino))
    Semaforo.wait(semaforo, self())
    # ---- Exclusión mútua ----
    request_SC = GlobalVars.get(globalvars, :request_SC)
    osn = GlobalVars.get(globalvars, :osn)
    defer_it = request_SC && ((osnVecino > osn) || (osnVecino == osn && idVecino > me)) && exclude(op1, op2)
    IO.puts("recibir_peticion #{me}: request_sc(#{request_SC}), osnVecino(#{osnVecino}), osn(#{osn}), idVecino(#{idVecino}), me(#{me}) --> defer_it(#{defer_it})")
    # ---- Fin exclusión mútua ----
    Semaforo.signal(semaforo)
    if (defer_it) do
        GlobalVars.set(globalvars, :listaAplazados, [GlobalVars.get(globalvars, :listaAplazados) | pidVecino])
    else
        send(pidVecino, :reply_SC)
    end
    recibir_peticion(globalvars, semaforo, me, op1)
 end

 defp recibir_reply(parent, oustanding_reply_count) do
    IO.puts("recibir_reply: outstanding_reply_count(#{outstanding_reply_count})")
    if (oustanding_reply_count == 0) do
        send(parent, :ok_SC)
    end
    receive do
        :reply_SC -> recibir_reply(parent, oustanding_reply_count-1)
    end
 end

 defp exclude(op1, op2) do
    matriz = %{
            update_resumen:     %{update_resumen: true, update_principal: false,update_entrega: false, read_resumen: true, read_principal: false,read_entrega: false},
            update_principal:   %{update_resumen: false, update_principal: true,update_entrega: false, read_resumen: false, read_principal: true,read_entrega: false},
            update_entrega:     %{update_resumen: false, update_principal: false,update_entrega: true, read_resumen: false, read_principal: false,read_entrega: true},
            read_resumen:       %{update_resumen: true, update_principal: false,update_entrega: false, read_resumen: false, read_principal: false,read_entrega: false},
            read_principal:     %{update_resumen: false, update_principal: true,update_entrega: false, read_resumen: true, read_principal: false,read_entrega: false},
            read_entrega:       %{update_resumen: false, update_principal: false,update_entrega: true, read_resumen: false, read_principal: false,read_entrega: false},
            }
    matriz[op1][op2]   
 end
end

defmodule GlobalVars do
    def start_link() do
        Agent.start_link(fn -> %{request_SC: nil, osn: nil, hsn: 0, listaAplazados: []} end)
    end

    def get(globalvars, var) do
        Agent.get(globalvars, fn mapa -> Map.get(mapa, var) end)
    end

    def set(globalvars, var, valor) do
        Agent.update(globalvars, fn mapa -> Map.replace(mapa, var, valor) end)
    end
end

defmodule Semaforo do
 def create() do
    spawn(fn -> semaforo(1, []) end)
 end

 def wait(semaforo, pid) do 
    send(semaforo, {:wait, pid})
    receive do
        :wait_ok -> :wait_ok
    end
 end

 def signal(semaforo) do
    send(semaforo, :signal)
 end

 defp semaforo(estado, listaEspera) do
    IO.puts("Semaforo: estado(#{estado}) listaEspera(#{listaEspera})")
    receive do
        :signal -> 
            if !Enum.empty(listaEspera) do      # Hay mas procesos esperando, se da permiso al primero
                primero = List.pop_at(1, listaEspera)
                send(primero, :ok)
                semaforo(0,listaEspera)
            else                                # No hay procesos esperando
                semaforo(1, listaEspera)
            end
        {:wait, pid} ->
            if estado == 1 do                   # Se otorga permiso directamente
                send(pid, :wait_ok)
                semaforo(0, listaEspera)
            else
                semaforo(0, [listaEspera|pid])  # Se añade a la cola 
            end
    end
 end
end
 