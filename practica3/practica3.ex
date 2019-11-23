Code.require_file("#{__DIR__}/nodo_remoto.exs")

defmodule Proxy do
  @moduledoc """
    Modulo que permite crear un proxy para recibir las peticiones de los clientes
  """

  @doc """
    Pone en marcha un proxy que recibe peticiones y crea procesos que atienden esa peticiones
  """
  def proxy(pidMaster) do
    # Recibir peticion y spawnear atender
    receive do
      {pid, value} -> spawn(Proxy, :atender, [pidMaster, pid, value])
    end
    proxy(pidMaster)
  end

  @doc """
    Proceso que envia la peticion del cliente al master, espera su resultado y lo envia al cliente
  """
  def atender(listaMasters, pid, value) do
    # Recibe respuestas
    pidRespuestas = spawn(fn -> Proxy.recibirResultados(%{}) end)
    # Envia peticion a masters
    Enum.each(listaMasters, fn nodo -> send({:master, nodo}, {:req, pidRespuestas, value}) end)
    # Elige mejor respuesta y la envia al cliente
    Process.sleep(2400)
    send(pidRespuestas, {:best_result, self()})
    respuestaFinal = receive do
      respuesta -> respuesta
    end
    send(pid, {:result, respuestaFinal})
  end

  def recibirResultados(resultados) do
    receive do
      # Devuelve el resultado que mas veces se repita
      {:best_result, pidProxy} ->
        if (Enum.empty?(resultados)) do
          send(pidProxy, 0)
        else
          send(pidProxy, elem(Enum.max_by(resultados, fn x -> elem(x, 1) end), 0))
        end
      # Añade los resultados a un mapa actualizando las veces que aparecen
      {:result_master, result} -> recibirResultados(Map.update(resultados, result, 1, &(&1 + 1)))
    end
  end

end

defmodule Master do
  @moduledoc """
    Modulo que permite crear un master cuya funcion es administrar la peticion del cliente y
  enviarsela a un worker
  """

  @doc """
    Crear un Master y ejecuta la lógica de elección de lider
  """
  def init(nodoPool) do
    Process.register(self(), :master)
    #IO.puts("Master creado")
    # Iniciar logica de eleccion de lider
    # Comenzar funcion master
    master(nodoPool)
  end

  @doc """
    Ejecuta la logica del master, recibe peticiones y crea procesos que las atiendan
  """
  defp master(nodoPool) do
    receive do
      {:req, pidProxy, value} -> spawn(Master, :atender, [pidProxy, nodoPool, value])
    end
    master(nodoPool)
  end

  @doc """
    Proceso que solicita un worker, le envia la carga de trabajo y devuelve el resultado al proxy
  """
  def atender(pidProxy, nodoPool, value) do
    pidWorker = Pool.pedirWorker(nodoPool)
    send(pidWorker, {:req, {self(), value}})
    receive do
      result ->
        send(pidProxy, {:result_master, result}) # Envio resultado a proxy
        Pool.liberarWorker(nodoPool, pidWorker)
        IO.inspect("Resultado a master = #{result}")
    after
      2500 -> Process.exit(pidWorker, :timeout)
    end
    #IO.puts("Master.atender -> resultado enviado y worker_free")
  end
end

defmodule Pool do
  @moduledoc """
    Modulo del pool de workers, crea y administra los workers
  """

  @doc """

  """
  def init(listaNodos, queue) do
    Enum.each(listaNodos, fn x -> spawn(Pool, :vigilante, [x, queue]) end)
    spawn(fn -> Pool.receiver_init(queue) end)
    spawn(fn -> Pool.request_init(queue) end)
  end

  def receiver_init(queue) do
    Process.register(self(), :pool_receiver)
    receiver(queue)
  end

  def request_init(queue) do
    Process.register(self(), :pool_request)
    request(queue)
  end

  defp receiver(queue) do
    receive do
      {:worker_free, pidWorker} -> Queue.push(queue, pidWorker)
    end
    receiver(queue)
  end

  defp request(queue) do
    receive do
      {:worker_req, pid} -> send(pid, {:worker, Queue.pop(queue)})
    end
    request(queue)
  end

  def liberarWorker(nodoPool, pidWorker) do
    send({:pool_receiver, nodoPool}, {:worker_free, pidWorker})
  end

  def pedirWorker(nodoPool) do
    send({:pool_request, nodoPool}, {:worker_req, self()})
    receive do
      {:worker, pidWorker} -> pidWorker
    end
  end

  def vigilante(nodoWorker, queue) do
    respuesta = Node.ping(nodoWorker)
    if respuesta == :pang do # Nodo caido
      # Iniciar nodo
      nombre = List.first(String.split(Atom.to_string(nodoWorker), "@"))
      host = List.last(String.split(Atom.to_string(nodoWorker), "@"))
      NodoRemoto.start(nombre, host, "/home/alberto/github/sistdistribuidos/practica3/workers.exs")
    end
    NodoRemoto.esperaNodoOperativo(nodoWorker, Worker)
    # Crear hijo
    Process.flag(:trap_exit, true)
    pidWorker = Node.spawn_link(nodoWorker, Worker, :init, [])
    Process.sleep(10300)
    Queue.push(queue, pidWorker)
    receive do
      {:EXIT, from_pid, reason} ->
        Queue.delete(queue, pidWorker)
        vigilante(nodoWorker, queue)
    end
  end
end

# FIFO List
defmodule Queue do
  def start_link() do
    spawn_link(fn -> queue([]) end)
  end

  def push(queue, value) do
    send(queue, {:push, value})
  end

  def pop(queue) do
    send(queue, {:pop, self()})
    receive do
      {:pop_ok, first} -> first
    end
  end

  def delete(queue, value) do
    send(queue, {:delete, value})
  end

  def queue(lista) do
    IO.inspect(lista)
    receive do
      {:push, value} -> queue(lista ++ [value])
      {:pop, pid} ->
        if !Enum.empty?(lista) do
          {first, n_lista} = List.pop_at(lista, 0)
          send(pid, {:pop_ok, first})
          queue(n_lista)
        else
          receive do # Se espera nuevo worker
            {:push, value} -> send(pid, {:pop_ok, value})
          end
          queue(lista)
        end
      {:delete, value} -> queue(List.delete(lista, value))
    end
  end
end

defmodule Maton do

end
