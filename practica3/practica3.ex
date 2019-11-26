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
    Envia la peticion del cliente al master, espera su resultado y lo envia al cliente
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

  @doc """
    Recibe los resultados de los master hasta que recibe un mensaje del proxy y envia el más repetido
  """
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
  def init(nodoPool, id, listaParticipantes) do
    Process.register(self(), :master)
    # Iniciar logica de eleccion de lider
    spawn(fn -> Maton.init(nodoPool, id, listaParticipantes) end)
    # Comenzar funcion master
    master(nodoPool)
  end

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
    after
      2500 -> Process.exit(pidWorker, :timeout)
    end
  end
end

defmodule Pool do
  @moduledoc """
    Modulo del pool de workers, crea y administra los workers
  """

  @doc """
    Para cada nodo donde se creara un worker, spawnea un vigilante.
    Crea un proceso que recibe liberaciones de workers y otro de peticiones
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

  @doc """
    Crea un proceso vigilante de un nodo y el worker que debe existir en el nodo
    Si no existe el nodo, lo crea y con él el worker mediante un enlace.
  """
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
      {:EXIT, _from_pid, _reason} ->
        Queue.delete(queue, pidWorker)
        vigilante(nodoWorker, queue)
    end
  end
end


defmodule Queue do
  @moduledoc """
    Modulo que implementa una cola, si la cola esta vacia, se bloquea hasta recibir un elemento
  """
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
  @moduledoc """
    Modulo que implementa el algoritmo del maton, esta compuesto por cuatro funciones o estados
  """
  def init(nodoPool, id, listaParticipantes) do
    Process.register(self(), :maton)
    listaVecinos = List.delete_at(listaParticipantes, id - 1)
    seguidor(nodoPool, id, listaParticipantes, listaVecinos)
  end

  def seguidor(nodoPool, id, listaParticipantes, listaVecinos) do
    IO.inspect("#{id}: Soy seguidor")
    receive do
      {:soy_lider, pidLider} -> seguidor(nodoPool, id, listaParticipantes, listaVecinos)
      {:eleccion, idSolicitante, pidSolicitante} ->
        contestar(id, idSolicitante, pidSolicitante)
        empezarEleccion(id, listaVecinos)
        espera_ok(nodoPool, id, listaParticipantes, listaVecinos)
      {:latido, pidLider} ->
        send(pidLider, :reply)
        seguidor(nodoPool, id, listaParticipantes, listaVecinos)
    after
      2000 -> empezarEleccion(id, listaVecinos)
              espera_ok(nodoPool, id, listaParticipantes, listaVecinos)

    end
  end

  def lider(nodoPool, id, listaParticipantes, listaVecinos, listaLatidos) do
    IO.inspect("Soy lider #{id}")
    receive do
      {:eleccion, idSolicitante, pidSolicitante} ->
        Enum.each(listaLatidos, fn latido -> Process.exit(latido, :fin_lider) end)
        contestar(id, idSolicitante, pidSolicitante)
        empezarEleccion(id, listaVecinos)
        espera_ok(nodoPool, id, listaParticipantes, listaVecinos)
    end
  end

  def espera_ok(nodoPool, id, listaParticipantes, listaVecinos) do
    IO.inspect("Espero_ok #{id}")
    receive do
      {:soy_lider, pidLider} -> seguidor(nodoPool, id, listaParticipantes, listaVecinos)
      {:eleccion, idSolicitante, pidSolicitante} -> contestar(id, idSolicitante, pidSolicitante)
                                                    espera_ok(nodoPool, id, listaParticipantes, listaVecinos)
      :ok -> espera_lider(nodoPool, id, listaParticipantes, listaVecinos)
    after
      500 -> Enum.each(listaVecinos, fn participante -> send({:maton, participante}, {:soy_lider, self()}) end)
             listaLatidos = iniciarLatidos(nodoPool, listaParticipantes, listaVecinos)
             lider(nodoPool, id, listaParticipantes, listaVecinos, listaLatidos)
    end
  end

  def espera_lider(nodoPool, id, listaParticipantes, listaVecinos) do
    IO.inspect("Espero_lider #{id}")
    receive do
      :ok -> espera_lider(nodoPool, id, listaParticipantes, listaVecinos)
      {:eleccion, idSolicitante, pidSolicitante} -> contestar(id, idSolicitante, pidSolicitante)
                                                    espera_lider(nodoPool, id, listaParticipantes, listaVecinos)
      {:soy_lider, pidLider} -> seguidor(nodoPool, id, listaParticipantes, listaVecinos)
    after
      2000 -> IO.inspect("No llega lider #{id}")
              empezarEleccion(id, listaVecinos)
              espera_ok(nodoPool, id, listaParticipantes, listaVecinos)
    end
  end

  defp empezarEleccion(id, listaVecinos) do
    IO.inspect("Inicio eleccion #{id}")
    participantesMayores = Enum.drop(listaVecinos, id - 1)
    Enum.each(participantesMayores, fn participante -> send({:maton, participante}, {:eleccion, id, self()}) end)
  end

  def iniciarLatidos(nodoPool, listaParticipantes, listaVecinos) do
    Enum.map(listaVecinos,
      fn participante ->
        spawn(
          fn ->
            latido(
              nodoPool,
              listaParticipantes,
              participante,
              Enum.find_index(listaVecinos, fn x -> x === participante end),
              0
            )
          end
        )
      end
    )
  end

  def latido(nodoPool, listaParticipantes, participante, id, veces) do
    #if (veces < 30) do
    Process.sleep(500)
    send({:maton, participante}, {:latido, self()})
    receive do
      :reply -> latido(nodoPool, listaParticipantes, participante, id, 0)
    after
      100 -> latido(nodoPool, listaParticipantes, participante, id, veces + 1)
    end
  end

  defp contestar(id, idSolicitante, pidSolicitante) do
    if (idSolicitante < id) do
      send(pidSolicitante, :ok)
    end
  end
end
