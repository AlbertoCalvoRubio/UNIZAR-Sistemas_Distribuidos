defmodule NodoRemoto do
  @moduledoc """
      modulo de gestión de ciclo de vida de nodos VM Elixir remotos
  """

  # Constantes
  @timeout_rpc 50

  @doc """
      Poner en marcha un nodo VM remoto con ssh
       - Se tiene en consideracion los puertos disponibles,
          debido al cortafuegos, en el laboratorio 1.02
  """
  @spec start(String.t(), String.t(), String.t()) :: node
  def start(nombre, host, fichero_programa_cargar) do
    IO.inspect(fichero_programa_cargar)
    System.cmd("ssh", [
      host,
      "elixir --name #{nombre}@#{host} --cookie palabrasecreta",
      "--erl  \'-kernel_inet_dist_listen_min 32000\'",
      "--erl  \'-kernel_inet_dist_listen_max 32049\'",
      "--erl -detached",
      "--no-halt #{fichero_programa_cargar}"
    ])

    # Devolver el atomo que referencia al nodo Elixir a poner en marcha
    nodo = String.to_atom(nombre <> "@" <> host)
    IO.inspect(nodo)
    nodo
  end

  @doc """
      Parar un nodo VM remoto por la via rapida
  """
  @spec stop(atom) :: no_return
  def stop(nodo) do
    # :rpc.block_call(nodo, :init, :stop, [])   estilo kill -15
    # estilo kill -9, ahora nos va
    :rpc.call(nodo, :erlang, :halt, [])

    # tambien habría que eliminar epmd, 
    # en el script shell externo
  end

  @doc """
      Eliminar el demonio epmd de un host con string
  """
  @spec killEpmd(String.t()) :: no_return
  def killEpmd(host) do
    System.cmd("ssh", [host, "pkill epmd"])
  end

  # Esperar hasta que nodo VM Elixir responda correctamente
  def esperaNodoOperativo(nodo, modulo) do
    # resultado rpc puede ser cualquier valor
    # El correcto es el nombre del modulo
    moduRemoto = :rpc.call(nodo, modulo, :__info__, [:module], @timeout_rpc)
    if moduRemoto != modulo, do: esperaNodoOperativo(nodo, modulo)
  end
end
