Code.require_file("servidor_gv.exs", __DIR__)

defmodule ClienteGV do
  @moduledoc """
      modulo de un cliente de gestor de vistas funcionando como nodo
  """

  # Constantes

  @tiempo_espera_de_respuesta 100

  @doc """
      Poner en marcha un nodo cliente del servicio de vistas
      Devolver atomo que referencia al nuevo nodo Elixir
  """
  @spec startNodo(String.t(), String.t()) :: node
  def startNodo(nombre_nodo, host) do
    # fichero en curso
    NodoRemoto.start(nombre_nodo, host, __ENV__.file)
  end

  @doc """
      Poner en marcha servicio trás esperar al pleno funcionamiento del nodo
  """
  @spec startService(node, node) :: boolean
  def startService(nodoElixir, nodo_servidor_gv) do
    NodoRemoto.esperaNodoOperativo(nodoElixir, __MODULE__)

    # Poner en marcha la funcionalidad del cliente de gestor de vistas
    Node.spawn(nodoElixir, __MODULE__, :init_cl, [nodo_servidor_gv])
    nodoElixir
  end

  @doc """
      Solicitar al cliente que envie un latido al servidor de vistas
  """
  @spec latido(node, integer) :: {ServidorGV.t_vista(), boolean}
  def latido(nodo_cliente, num_vista) do
    send({:cliente_gv, nodo_cliente}, {:envia_latido, num_vista, self()})

    # esperar respuesta del latido
    receive do
      {:vista_tentativa, vista, is_ok?} -> {vista, is_ok?}
    after
      @tiempo_espera_de_respuesta ->
        {ServidorGV.vista_inicial(), false}
    end
  end

  @doc """
      Solicitar al cliente que envie una petición de obtención de vista válida
  """
  @spec obten_vista(atom) :: {ServidorGV.t_vista(), boolean}
  def obten_vista(nodo_cliente) do
    send({:cliente_gv, nodo_cliente}, {:obten_vista_valida, self()})

    # esperar respuesta del latido
    receive do
      {:vista_valida, vista, is_ok?} -> {vista, is_ok?}
    after
      @tiempo_espera_de_respuesta ->
        {ServidorGV.vista_inicial(), false}
    end
  end

  @doc """
      Solicitar al cliente que consiga el primario del servicio de vistas
  """
  @spec primario(atom) :: node
  def primario(nodo_cliente) do
    resultado = obten_vista(nodo_cliente)

    case resultado do
      {vista, true} -> vista.primario
      {_vista, false} -> :undefined
    end
  end

  # ------------------ Funciones privadas

  def init_cl(nodo_servidor_gv) do
    Process.register(self(), :cliente_gv)
    bucle_recepcion(nodo_servidor_gv)
  end

  defp bucle_recepcion(nodo_servidor_gv) do
    receive do
      {:envia_latido, num_vista, pid_maestro} ->
        procesa_latido(nodo_servidor_gv, num_vista, pid_maestro)

      {:obten_vista_valida, pid_maestro} ->
        procesa_obten_vista(nodo_servidor_gv, pid_maestro)
    end

    bucle_recepcion(nodo_servidor_gv)
  end

  defp procesa_latido(nodo_servidor_gv, num_vista, pid_maestro) do
    send({:servidor_gv, nodo_servidor_gv}, {:latido, num_vista, Node.self()})

    # esperar respuesta del latido
    receive do
      {:vista_tentativa, vista, encontrado?} ->
        send(pid_maestro, {:vista_tentativa, vista, encontrado?})
    after
      @tiempo_espera_de_respuesta ->
        send(pid_maestro, {:vista_tentativa, ServidorGV.vista_inicial(), false})
    end
  end

  defp procesa_obten_vista(nodo_servidor_gv, pid_maestro) do
    send({:servidor_gv, nodo_servidor_gv}, {:obten_vista_valida, self()})

    receive do
      {:vista_valida, vista, coincide?} ->
        send(pid_maestro, {:vista_valida, vista, coincide?})
    after
      @tiempo_espera_de_respuesta ->
        send(pid_maestro, {:vista_valida, ServidorGV.vista_inicial(), false})
    end
  end
end
