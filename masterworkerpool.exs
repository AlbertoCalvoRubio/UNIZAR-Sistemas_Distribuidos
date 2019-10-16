# AUTORES: Alberto Calvo Rubio, Oscar Baselga Lahoz
# NIAs: 760739, 760077
# FICHERO: master.exs
# FECHA: 15/10/19
# TIEMPO:
# DESCRIPCION: modulo del master

defmodule Master do
use Fib

    def atender(pidPool, pidCliente, op, lista, n) do
        send(pidPool, {self(), :request})
        receive do
            {:reply, pidWorker} -> send(pidWorker, {self(), op, lista, n})
        end
        receive do
            {:resultadoWorker, resultado} -> send(pidPool, {:fin, pidWorker})
        end
        send(pidCliente, resultado)
    end

    # Escucha de peticiones atendiendolas en diferentes procesos para no secuencializar
    def listen(pidPool) do 
        listen(pidPool)
        receive do
            {pidCliente, op, lista, n} -> spawn(fn -> atender(pidPool, pidCliente, op, lista, n) end)
        end
        listen(pidPool)
    end

    # Inicializacion del sistema empezando por el Master
    def initMaster(nodoPool, nodosWorker) do
        # Lanzamiento del pool
        pidPool = Node.spawn(nodoPool, fn -> initPool(nodosWorker, cargasWorkers) end)
        # Funcionamineto del master
        listen(pidPool)
    end


    # Worker

    def initWorker do
        receive do
            {:peticion, pidMaster, op, lista, n} -> work(pidMaster, listaCalcular, op, n)
        end
        
    end

    def work(pidMaster, listaCalcular, op, veces) do
        case op do
            :fib -> resultado = Enum.map(listaCalcular, fibonnaci)
            :fib_tr -> resultado = Enum.map(listaCalcular, fibonacci_tr)
        end
        send(pidMaster, {:resultadoWorker, resultado})
    end
end

defmodule Pool do

    # Llamado desde initMaster()
    # Almacena la informacion de las maquinas worker (pasadas como un map[id,4]) y llama a controlarWorkers()
    def initPool(maquinas_workers,carga_maquinas) do
        spawn fn -> controlarWorkers(maquinas_workers,carga_maquinas) end
    end

    # Recibe las peticiones del master (:request) y le responde con el 
    # PID del nuevo worker y el ID de la maquina en la que se encuentra (:reply)
    # Tambien recibe el PID de los workers terminados (finWorker())
    def controlarWorkers(maquinas_workers,carga_maquinas) do
        
        bestWorker = Enum.min(carga_maquinas)

        if bestWorker == 4 do
            receive do
                {:fin,pidWorker} -> List.update_at(carga_maquinas, Enum.find_index(carga_maquinas, fn x -> x == pidWorker end), &(&1 - 1))
            end
        end

        indexBestWorker = Enum.find_index(carga_maquinas, fn x -> x == bestWorker end)
        bestWorker = Enum.at(maquinas_workers,indexBestWorker)

        pidBestWorker = Node.spawn(bestWorker, fn -> initWorker() end)
        List.update_at(carga_maquinas, indexBestWorker, &(&1 + 1))

        receive do
            {pidAtenderMaster,:request} -> send(pidAtenderMaster,{:reply,pidBestWorker})
            {:fin,pidWorker} -> List.update_at(carga_maquinas, Enum.find_index(carga_maquinas, fn x -> x == pidWorker end), &(&1 - 1))
        end

        controlarWorkers(maquinas_workers,carga_maquinas)
    end
end