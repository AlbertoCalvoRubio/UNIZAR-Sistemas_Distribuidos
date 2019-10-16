# AUTORES:
# fuentes: 
# FICHERO: fibonacci.exs
# FECHA: 
# TIEMPO: 
# DESCRIPCION: 

defmodule Fib do
	def fibonacci(0), do: 0
	def fibonacci(1), do: 1
	def fibonacci(n) when n >= 2 do
		fibonacci(n - 2) + fibonacci(n - 1)
	end
	def fibonacci_tr(n), do: fibonacci_tr(n, 0, 1)
	defp fibonacci_tr(0, _acc1, _acc2), do: 0
	defp fibonacci_tr(1, _acc1, acc2), do: acc2
	defp fibonacci_tr(n, acc1, acc2) do
		fibonacci_tr(n - 1, acc2, acc1 + acc2)
	end

	@golden_n :math.sqrt(5)
  	def of(n) do
 		(x_of(n) - y_of(n)) / @golden_n
	end
 	defp x_of(n) do
		:math.pow((1 + @golden_n) / 2, n)
	end
	def y_of(n) do
		:math.pow((1 - @golden_n) / 2, n)
	end
end	

defmodule Cliente do

  def launch(pid, op, 1) do
	send(pid, {self, op, 1..36, 1})
	receive do 
		{:result, l} -> l
	end
  end

  def launch(pid, op, n) when n != 1 do
	send(pid, [self, op, 1..36, n])
	spawn fn -> receive do 
				{:solucion,result} -> result
				end
	end
	launch(pid, op, n - 1)
  end 
  
  def genera_workload(server_pid, escenario, time) do
	cond do
		time <= 3 ->  launch(server_pid, :fib, 8); Process.sleep(2000)
		time == 4 ->  launch(server_pid, :fib, 8);Process.sleep(round(:rand.uniform(100)/100 * 2000))
		time <= 8 ->  launch(server_pid, :fib, 8);Process.sleep(round(:rand.uniform(100)/1000 * 2000))
		time == 9 -> launch(server_pid, :fib_tr, 8);Process.sleep(round(:rand.uniform(2)/2 * 2000))
	end
  	genera_workload(server_pid, escenario, rem(time + 1, 10))
  end

  def genera_workload(server_pid, escenario) do
  	if escenario == 1 do
		launch(server_pid, :fib, 1)
	else
		launch(server_pid, :fib, 4)
	end
	Process.sleep(2000)
  	genera_workload(server_pid, escenario)
  end
  

  def cliente(server_pid, tipo_escenario) do
  	case tipo_escenario do
		:uno -> genera_workload(server_pid, 1)
		:dos -> genera_workload(server_pid, 2)
		:tres -> genera_workload(server_pid, 3, 1)
	end
  end
end

defmodule Worker do
	def initWorker() do
        receive do
            {:peticion, pidMaster, op, lista, n} -> work(pidMaster, lista, op, n)
        end
    end

    def work(pidMaster, listaCalcular, op, veces) do
        resultado= 
            case op do
                :fib -> resultado = Enum.map(listaCalcular, Fib.fibonnaci)
                :fib_tr -> resultado = Enum.map(listaCalcular, Fib.fibonacci_tr)
            end
        send(pidMaster, {:resultadoWorker, self(), resultado})
    end
end


defmodule Pool do
import Worker

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

defmodule Master do
import Pool

    def atender(pidPool, pidCliente, op, lista, n) do
        send(pidPool, {self(), :request})
        receive do
            {:reply, pidWorker} -> send(pidWorker, {self(), op, lista, n})
        end
        receive do
            {:resultadoWorker, pidWorker, resultado} -> send(pidPool, {:fin, pidWorker}); send(pidCliente, resultado)
        end
        
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
    def initMaster(nodoPool, nodosWorker, cargasWorkers) do
        # Lanzamiento del pool
        pidPool = Node.spawn(nodoPool, fn -> initPool(nodosWorker, cargasWorkers) end)
        # Funcionamineto del master
        listen(pidPool)
    end
end




