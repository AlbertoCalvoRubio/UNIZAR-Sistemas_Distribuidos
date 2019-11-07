# AUTOR: Oscar Baselga y Alberto Calvo
 # FICHERO: para_repositorio.ex
 # FECHA: 26 de octubre de 2019
 # TIEMPO: 20 horas
 # DESCRIPCION: modulo para un repositorio al que acceden lectores y escritores de forma distribuida

defmodule Para_Repositorio do
 def lanzarProcesos(pidRepo, 1, listaNodos, operaciones) do
    nodo = Enum.at(listaNodos, 0)
    op = Enum.random(operaciones)
    if (Enum.member?([:update_resumen, :update_principal, :update_entrega], op)) do
        Node.spawn(nodo, Para_Repositorio, :escritor, [pidRepo, 1, listaNodos, op])
    else
        Node.spawn(nodo, Para_Repositorio, :lector, [pidRepo, 1, listaNodos, op])
    end
 end

 def lanzarProcesos(pidRepo, n, listaNodos, operaciones) do 
    nodo = Enum.at(listaNodos, n-1)
    op = Enum.random(operaciones)
    if (Enum.member?([:update_resumen, :update_principal, :update_entrega], op)) do
        Node.spawn(nodo, Para_Repositorio, :escritor, [pidRepo, n, listaNodos, op])
    else
        Node.spawn(nodo, Para_Repositorio, :lector, [pidRepo, n, listaNodos, op])
    end
    lanzarProcesos(pidRepo, n-1, listaNodos, operaciones)
 end
 
 def lector(pidRepo, me, listaNodos, op_lectura) do
    {listaVecinos, numVecinos, globalvars, semaforo} = init(listaNodos, me)
    spawn(fn -> recibir_peticion_init(globalvars, semaforo, me, op_lectura) end)
    #Process.sleep(round(:rand.uniform(100)/100 * 2000)) # Simulacion para tener distintos osn
    pre_protocol(globalvars, semaforo, listaVecinos, numVecinos, me, op_lectura)
    # ---- Inicio SC ----
    Process.sleep(3000)
    send(pidRepo, {op_lectura, self()})
    receive do
        {:reply, texto} -> IO.inspect("Nodo #{me} -> he leido: #{texto}")
    end
    # ----- Fin SC ------
    post_protocol(globalvars)
 end

 def escritor(pidRepo, me, listaNodos, op_escritura) do
    {listaVecinos, numVecinos, globalvars, semaforo} = init(listaNodos, me)
    spawn(fn -> recibir_peticion_init(globalvars, semaforo, me, op_escritura) end)
    #Process.sleep(round(:rand.uniform(100)/100 * 2000)) # Simulacion para tener distintos osn
    pre_protocol(globalvars, semaforo, listaVecinos, numVecinos, me, op_escritura)
    # ---- Inicio SC ----
    Process.sleep(3000)
    send(pidRepo, {op_escritura, self(), me})
    receive do
        {:reply, :ok} -> IO.inspect("Nodo #{me} -> he escrito")
    end
    # ----- Fin SC ------
    post_protocol(globalvars)
 end

  defp init(listaNodos, me) do
    listaVecinos = List.delete_at(listaNodos, me-1) # Se borra el nodo de si mismo
    numVecinos = length(listaVecinos)
    {:ok, globalvars} = GlobalVars.start_link()
    semaforo = Semaforo.create()
    {listaVecinos, numVecinos, globalvars, semaforo}
 end
 
 defp pre_protocol(globalvars, semaforo, listaVecinos, numVecinos, me, op_t) do
    pid = self()
    Semaforo.wait(semaforo, pid)
    # ---- Exclusión mútua ----
    GlobalVars.set(globalvars, :request_SC, :true)  # request_SC = true
    osn = GlobalVars.get(globalvars, :hsn) + 1      # osn = hsn + 1
    GlobalVars.set(globalvars, :osn, osn)
    # ---- Fin exclusión mútua ----
    Semaforo.signal(semaforo)
    pidListener = spawn(fn -> recibir_reply(pid, numVecinos) end) # Se escucha las respuestas de los demas procesos
    enviar_peticiones(listaVecinos, pidListener, osn, me, op_t)
 end

 defp post_protocol(globalvars) do
    GlobalVars.set(globalvars, :request_SC, :false)  # request_SC = false
    listaAplazados = GlobalVars.get(globalvars, :listaAplazados)
    Enum.each(listaAplazados, fn aplazado -> send(aplazado, :reply_SC) end) # Contestar a cada proceso
    GlobalVars.set(globalvars, :globalvars, []) # Vaciar lista de aplazados, ya se han contestado 
 end

 defp recibir_peticion_init(globalvars, semaforo, me, op1) do
    Process.register(self(), :recibir_peticion)
    recibir_peticion(globalvars, semaforo, me, op1)
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
    IO.inspect("Nodo #{me} -> Peticion de #{idVecino}: defer_it(#{defer_it}) --> request_sc(#{request_SC}), osnVecino(#{osnVecino}), osn(#{osn}), idVecino(#{idVecino}), op1(#{op1}), op2(#{op2})")
    # ---- Fin exclusión mútua ----
    Semaforo.signal(semaforo)
    if (defer_it) do
        GlobalVars.set(globalvars, :listaAplazados, GlobalVars.get(globalvars, :listaAplazados) ++ [pidVecino])
    else
        send(pidVecino, :reply_SC)
    end
    recibir_peticion(globalvars, semaforo, me, op1)
 end

 defp recibir_reply(parent, oustanding_reply_count) do
    if (oustanding_reply_count == 0) do
        send(parent, :ok_SC)
    else
        receive do
            :reply_SC -> recibir_reply(parent, oustanding_reply_count-1)
        end
    end
 end  

 defp enviar_peticiones(listaVecinos, pidListener, osn, me, op_t) do
    Enum.each(listaVecinos, fn nodoVecino -> send({:recibir_peticion, nodoVecino}, {:request_SC, pidListener, osn, me, op_t}) end) # Enviar peticiones
    receive do  # Esperar al permiso para entrar en SC
        :ok_SC -> :ok
    after
        1_000 -> enviar_peticiones(listaVecinos, pidListener, osn, me, op_t)
    end
 end

 # Matriz que define y devuelve la exclusion entre operaciones
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

# Modulo que permite crear un proceso que mantiene las variables globales cada lector/escritor, consultar su valor y cambiarlo
defmodule GlobalVars do
    def start_link() do
        Agent.start_link(fn -> %{request_SC: false, osn: nil, hsn: 0, listaAplazados: []} end)
    end

    def get(globalvars, var) do
        Agent.get(globalvars, fn mapa -> Map.get(mapa, var) end)
    end

    def set(globalvars, var, valor) do
        Agent.update(globalvars, fn mapa -> Map.replace(mapa, var, valor) end)
    end
end

# Modulo que permite crear un semaforo en elixir con una cola de espera
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

 def semaforo(estado, listaEspera) do
    receive do
        :signal -> 
            if !Enum.empty?(listaEspera) do      # Hay mas procesos esperando, se da permiso al primero
                {primero, listaEspera} = List.pop_at(listaEspera, 0)
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
                semaforo(0, listaEspera ++ [pid])  # Se añade a la cola 
            end
    end
 end
end
 