# AUTORES: Oscar Baselga Lahoz y Alberto Calvo Rubió
# NIAs: 760077 y 760739
# FICHERO: escenario2.ex
# FECHA: 15/10/19
# TIEMPO: 
# DESCRIPCION: escenario 1 de la practica1 con la implementacion de un cliente-servidor

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
	    send(pid, {:req, pidEscuchar, op, 1..36, 1})
    
  end

def launch(pid, op, n) when n != 1 do
    tiempoInicial = Time.utc_now
    pidEscuchar = spawn(fn -> escuchar(tiempoInicial) end)
    send(pid, {:req, pidEscuchar, op, 1..36,n})
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

defmodule Servidor do
    def server() do
        receive do
        {:req, pidCliente, op, lista, veces} -> spawn(fn -> calcular(pidCliente, op, lista) end)
        end
        server()
    end

    def calcular(pidCliente, op, lista) do
        tiempoInicio = Time.utc_now
        resultado =
            case op do
                :fib -> Enum.map(lista, fn x -> Fib.fibonacci(x) end)
                :fib_tr -> Enum.map(lista, fn x -> Fib.fibonacci_tr(x) end)
            end
        tiempoEjecucion = Time.diff(Time.utc_now, tiempoInicio, :milliseconds)
        IO.puts("Tiempo ejecucion: #{tiempoEjecucion}")
        send(pidCliente, {:result, resultado})
    end              
end