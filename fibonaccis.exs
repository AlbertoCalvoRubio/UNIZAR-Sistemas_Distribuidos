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
	send(pid, {self(), op, 1..36, 1})
	receive do 
		{:result, l} -> l
	end
  end

  def launch(pid, op, n) when n != 1 do
    spawn fn -> launch(pid, op, 1) end
	launch(pid, op, n - 1)
  end 
  
  def genera_workload(server_pid, escenario, time) do
    tiempo1 = Time.utc_now
	cond do
		time <= 3 ->  launch(server_pid, :fib, 8); Process.sleep(2000)
		time == 4 ->  launch(server_pid, :fib, 8);Process.sleep(round(:rand.uniform(100)/100 * 2000))
		time <= 8 ->  launch(server_pid, :fib, 8);Process.sleep(round(:rand.uniform(100)/1000 * 2000))
		time == 9 -> launch(server_pid, :fib_tr, 8);Process.sleep(round(:rand.uniform(2)/2 * 2000))
	end
    tiempoTotal = Time.diff(Time.utc_now, tiempo1, :milliseconds)
    IO.puts("Tiempo total: #{tiempoTotal}")
  	genera_workload(server_pid, escenario, rem(time + 1, 10))
  end

  def genera_workload(server_pid, escenario) do
    tiempo1 = Time.utc_now
  	if escenario == 1 do
		launch(server_pid, :fib, 1)
	else
		launch(server_pid, :fib, 4)
	end
    tiempoTotal = Time.diff(Time.utc_now, tiempo1, :milliseconds)
    IO.puts("Tiempo total: #{tiempoTotal}")
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
	def initWorker(pidPool) do
        receive do
            {:peticion, pidCliente, op, lista, n} -> work(pidPool, pidCliente, lista, op, n)
        end
    end

    def work(pidPool, pidCliente, listaCalcular, op, veces) do
        if op == :fib do
            tiempo1 = Time.utc_now
            resultado = Enum.map(listaCalcular, fn x -> Fib.fibonacci(x) end)
            tiempoEjecucion = Time.diff(Time.utc_now, tiempo1, :milliseconds)
            IO.puts("Tiempo ejecucion: #{tiempoEjecucion}")
            send(pidCliente, {:result, resultado})
        else
            tiempo1 = Time.utc_now
            resultado = Enum.map(listaCalcular, fn x -> Fib.fibonacci_tr(x) end)
            tiempoEjecucion = Time.diff(Time.utc_now, tiempo1, :milliseconds)
            IO.puts("Tiempo ejecucion: #{tiempoEjecucion}")
            send(pidCliente, {:result, resultado})
        end
        send(pidPool, {:fin, self()})
        IO.puts("fin worker")
    end
end


defmodule Pool do

    # Almacena la informacion de las maquinas worker (pasadas como un map[id,4]) y llama a controlarWorkers()
    def initPool(maquinas_workers,carga_maquinas) do
        bestWorker = Enum.min(carga_maquinas)
        IO.inspect(carga_maquinas, label: "carga1: ")
        #carga_maquinas = List.update_at(carga_maquinas, Enum.find_index(carga_maquinas, fn x -> x == pidWorker end), &(&1 - 1));
        if bestWorker == 4 do
            receive do
                {:fin,pidWorker} -> IO.inspect(carga_maquinas, label: "carga4: ")
            end
        end
        IO.inspect(carga_maquinas, label: "carga2: ")

        indexBestWorker = Enum.find_index(carga_maquinas, fn x -> x == bestWorker end)
        bestWorker = Enum.at(maquinas_workers,indexBestWorker)

        pidBestWorker = Node.spawn(bestWorker, fn -> Worker.initWorker(self()) end)

        carga_maquinas = List.update_at(carga_maquinas, indexBestWorker, &(&1 + 1))
        IO.puts("bestWorker: #{bestWorker}")
        receive do
            {pidAtenderMaster,:request} -> send(pidAtenderMaster,{:reply,pidBestWorker})
            {:fin,pidWorker} -> IO.inspect(carga_maquinas, label: "carga4: ")
        end
        IO.inspect(carga_maquinas, label: "carga3: ")
        initPool(maquinas_workers,carga_maquinas)
    end
end

defmodule Master do

    def atender(pidPool, pidCliente, op, lista, n) do
        send(pidPool, {self(), :request})
        receive do
            {:reply, pidWorker} -> send(pidWorker, {:peticion, pidCliente, op, lista, n})
        end
    end

    # Inicializacion del sistema empezando por el Master
    def initMaster(pidPool) do
        receive do
            {pidCliente, op, lista, n} -> spawn(fn -> atender(pidPool, pidCliente, op, lista, n) end)
        end
        initMaster(pidPool)
    end
end




