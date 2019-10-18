# AUTORES: Oscar Baselga Lahoz y Alberto Calvo Rubió
# NIAs: 760077 y 760739
# FICHERO: fibonaccis.exs
# FECHA: 15/10/19
# TIEMPO: 
# DESCRIPCION: modulos fibonacci, cliente, master, worker para un despliegue de un sistema

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
        tiempoInicial = Time.utc_now
        pidEscuchar = spawn(fn -> escuchar(tiempoInicial) end)
	    send(pid, {pidEscuchar, op, 1..36, 1})
    
  end

def launch(pid, op, n) when n != 1 do
    tiempoInicial = Time.utc_now
    pidEscuchar = spawn(fn -> escuchar(tiempoInicial) end)
    send(pid, {pidEscuchar, op, 1..36,n})
	launch(pid, op, n - 1)
  end 

  def escuchar(tiempoInicial) do
    receive do
        {:result, l} -> l
    end
    tiempoTotal = Time.diff(Time.utc_now, tiempoInicial, :milliseconds)
    IO.puts("Tiempo total ---> #{tiempoTotal}")
  end
  
  def genera_workload(server_pid, escenario, time) do
    IO.puts("Time: #{time}")
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
            {:peticion, pidEscuchar, pidPool, op, lista, n} -> work(pidEscuchar, pidPool, lista, op, n)
        end
    end

    def work(pidEscuchar, pidPool, listaCalcular, op, veces) do
        if op == :fib do
            tiempo1 = Time.utc_now
            resultado = Enum.map(listaCalcular, fn x -> Fib.fibonacci(x) end)
            tiempoEjecucion = Time.diff(Time.utc_now, tiempo1, :milliseconds)
            IO.puts("Tiempo ejecucion: #{tiempoEjecucion}")
            send(pidEscuchar, {:result, resultado})
        else
            tiempo1 = Time.utc_now
            resultado = Enum.map(listaCalcular, fn x -> Fib.fibonacci_tr(x) end)
            tiempoEjecucion = Time.diff(Time.utc_now, tiempo1, :milliseconds)
            IO.puts("Tiempo ejecucion: #{tiempoEjecucion}")
            send(pidEscuchar, {:result, resultado})
        end
        send(pidPool, {:fin, node()})
    end
end


defmodule Pool do

    def initPool(maquinas_workers,carga_maquinas) do
        bestWorker = Enum.min(carga_maquinas)
        if bestWorker == 4 do
            receive do
                {:fin,nodeWorker} -> initPool(maquinas_workers,List.update_at(carga_maquinas, Enum.find_index(maquinas_workers, fn x -> x == nodeWorker end), &(&1 - 1)))
            end
        else
            indexBestWorker = Enum.find_index(carga_maquinas, fn x -> x == bestWorker end)
            bestWorker = Enum.at(maquinas_workers,indexBestWorker)
            pidBestWorker = Node.spawn(bestWorker, fn -> Worker.initWorker() end)
            # IO.puts("bestWorker: #{bestWorker}") # Ver que son de maquinas diferentes
            receive do
                {:fin,nodeWorker} -> initPool(maquinas_workers,List.update_at(carga_maquinas, Enum.find_index(maquinas_workers, fn x -> x == nodeWorker end), &(&1 - 1)))
                {:request, pidAtenderMaster} -> send(pidAtenderMaster,{:reply,pidBestWorker});initPool(maquinas_workers, List.update_at(carga_maquinas, indexBestWorker, &(&1 + 1)))
                
            end
        end
    end
end

defmodule Master do

    def atender(pidEscuchar, pidPool, op, lista, n) do
        # Peticion de worker a Pool
        send(pidPool, {:request, self()})
        # Recepcion del worker y envio de trabajo
        receive do
            {:reply, pidWorker} -> send(pidWorker, {:peticion, pidEscuchar, pidPool, op, lista, n})
        end
    end

    # Inicializacion del sistema empezando por el Master
    def initMaster(pidPool) do
        receive do
            {pidEscuchar, op, lista, n} -> spawn(fn -> atender(pidEscuchar, pidPool, op, lista, n) end)
        end
        initMaster(pidPool)
    end
end




