require IEx # Para utilizar IEx.pry

defmodule ServidorGV do
  @moduledoc """
      modulo del servicio de vistas
  """

  # Tipo estructura de datos que guarda el estado del servidor de vistas
  # COMPLETAR  con lo campos necesarios para gestionar
  # el estado del gestor de vistas
  defstruct num_vista: 0, primario: :undefined, copia: :undefined

  # Constantes
  @latidos_fallidos 4

  @intervalo_latidos 50


  @doc """
      Acceso externo para constante de latidos fallios
  """
  def latidos_fallidos() do
    @latidos_fallidos
  end

  @doc """
      acceso externo para constante intervalo latido
  """
  def intervalo_latidos() do
    @intervalo_latidos
  end

  @doc """
      Generar un estructura de datos vista inicial
  """
  def vista_inicial() do
    %{num_vista: 0, primario: :undefined, copia: :undefined}
  end

  @doc """
      Poner en marcha el servidor para gestión de vistas
      Devolver atomo que referencia al nuevo nodo Elixir
  """
  @spec startNodo(String.t, String.t) :: node
  def startNodo(nombre, maquina) do
    # fichero en curso
    NodoRemoto.start(nombre, maquina, __ENV__.file)
  end

  @doc """
      Poner en marcha servicio trás esperar al pleno funcionamiento del nodo
  """
  @spec startService(node) :: boolean
  def startService(nodoElixir) do
    NodoRemoto.esperaNodoOperativo(nodoElixir, __MODULE__)
    IO.puts("Nodo operativo")

    # Poner en marcha el código del gestor de vistas
    Node.spawn(nodoElixir, __MODULE__, :init_sv, [])
  end

  #------------------- FUNCIONES PRIVADAS ----------------------------------

  # Estas 2 primeras deben ser defs para llamadas tipo (MODULE, funcion,[])
  def init_sv() do
    Process.register(self(), :servidor_gv)

    spawn(__MODULE__, :init_monitor, [self()]) # otro proceso concurrente

    #### VUESTRO CODIGO DE INICIALIZACION

    bucle_recepcion(vista_inicial(), vista_inicial(), [], true)
  end

  def init_monitor(pid_principal) do
    send(pid_principal, :procesa_situacion_servidores)
    Process.sleep(@intervalo_latidos)
    init_monitor(pid_principal)
  end

  defp bucle_recepcion(vista_valida, vista_tentativa, latidos, consistente) do
    if (consistente) do
      receive do
        {:latido, n_vista_latido, nodo_emisor} ->
          IO.puts("Latido recibido")
          if (n_vista_latido == 0) do # Caida
            {vista_valida, vista_tentativa, latidos, consistente} =
              tratar_caida(vista_valida, vista_tentativa, latidos, nodo_emisor)
            enviar_tentativa(vista_valida, vista_tentativa, nodo_emisor)
            ##IO.inspect(vista_tentativa)
            bucle_recepcion(vista_valida, vista_tentativa, latidos, consistente)

          else # Caso normal
            latidos = reset_latidos(latidos, nodo_emisor)

            # Posible confimacion vista del primario
            vista_valida = confirmar_vista(n_vista_latido, vista_valida,
              vista_tentativa, nodo_emisor)

            enviar_tentativa(vista_valida, vista_tentativa, nodo_emisor)
            #IO.inspect(vista_tentativa)
            bucle_recepcion(vista_valida, vista_tentativa, latidos, consistente)
          end

        {:obten_vista_valida, pid} ->
          IO.puts(":obten_vista_valida recibido")
          # Devolver vista valida
          send(pid, {:vista_valida, vista_valida, vista_valida == vista_tentativa})
          #IO.inspect(vista_tentativa)
          bucle_recepcion(vista_valida, vista_tentativa, latidos, consistente)


        :procesa_situacion_servidores ->
          IO.puts(":procesa_situacion_servidores recibido")
          # Actualizar situacion de servidores si es necesario
          {vista_valida, vista_tentativa, latidos, consistente} =
            procesa_situacion_servidores(vista_valida, vista_tentativa, latidos,
              consistente)
          #IO.inspect(vista_tentativa)
          bucle_recepcion(vista_valida, vista_tentativa, latidos, consistente)
      end
    else
      IO.puts("END: Estado del sistema no consistentem parada critica")
    end
  end

  # OTRAS FUNCIONES PRIVADAS VUESTRAS
  defp procesa_situacion_servidores(vista_valida, vista_tentativa, latidos,
         consistente) do
    if (!Enum.empty?(latidos)) do
      # Actualizar latidos de cada servidor
      latidos = for i <- latidos, do: {elem(i, 0), elem(i, 1) + 1}

      # Se eliminan los nodos con más de @latidos_fallidos
      latidos = borrar_caidos(latidos)

      # Comprobar servidores caidos
      # POSIBLE ERROR? ALOMEJOR DEBERIA SER DE LA VISTA_TENTATIVA
      primario_caido? = (vista_tentativa.primario != :undefined
        && !List.keymember?(latidos, vista_tentativa.primario, 0))
      copia_caido? = (vista_tentativa.copia != :undefined
        && !List.keymember?(latidos, vista_tentativa.copia, 0))

      {vista_valida, vista_tentativa, latidos, consistente} =
        actualizar_servidores(primario_caido?, copia_caido?, vista_valida,
          vista_tentativa, latidos)

      {vista_valida, vista_tentativa, latidos, consistente}
    else
      {vista_valida, vista_tentativa, latidos, consistente}
    end
  end

  defp tratar_caida(vista_valida, vista_tentativa, latidos, nodo_emisor) do
    #IO.inspect(nodo_emisor)
    primario_caido? = (vista_tentativa.primario == nodo_emisor
      && List.keymember?(latidos, nodo_emisor, 0))
    copia_caido? = (vista_tentativa.copia == nodo_emisor
                    && List.keymember?(latidos, nodo_emisor, 0))
    #IO.inspect(vista_tentativa)
    #IO.inspect(copia_caido?)
    # Se elimina de los latidos en caso de existir
    latidos = List.keydelete(latidos, nodo_emisor, 0)

    # Se comprueba si va a ser primario, copia o en espera
    vista_tentativa =
      case vista_tentativa.num_vista do
        0 -> %{vista_tentativa |
          num_vista: vista_tentativa.num_vista + 1,
          primario: nodo_emisor}
        1 -> %{vista_tentativa |
               num_vista: vista_tentativa.num_vista + 1,
               copia: nodo_emisor}
        _ -> if (vista_tentativa.copia == :undefined) do
               # Nuevo nodo se convierte en copia
               %{vista_tentativa |
                 num_vista: vista_tentativa.num_vista + 1,
                 copia: nodo_emisor}
             else
              vista_tentativa
             end
      end

    # Nuevo nodo en latidos
    latidos = latidos ++ [{nodo_emisor, 0}]

    {vista_valida, vista_tentativa, latidos, consistente} =
      actualizar_servidores(primario_caido?, copia_caido?, vista_valida,
        vista_tentativa, latidos)


    {vista_valida, vista_tentativa, latidos, consistente}
  end

  defp reset_latidos(latidos, nodo_emisor) do
    latidos = for i <- latidos do
      if (elem(i, 0) == nodo_emisor) do
        {elem(i, 0), 0}
      else
        i
      end
    end
    latidos
  end

  # Borra de latidos, los servidores con más de @latidos_fallidos
  defp borrar_caidos(latidos) do
    latidos = Enum.filter(latidos,
      fn latido -> elem(latido, 1) <= @latidos_fallidos end)
    latidos
  end

  # Se envia vista_tentativa al nodo_emisor
  defp enviar_tentativa(vista_valida, vista_tentativa, nodo_emisor) do
    send(
      {:cliente_gv, nodo_emisor},{:vista_tentativa, vista_tentativa,
      vista_valida == vista_tentativa})
  end

  # Si el nodo emisor es el nodo primario y ha devuelto la misma vista, se
  # se devuelve la vista_tentativa, sino se mantiene la anterior vista_valida
  defp confirmar_vista(n_vista_latido, vista_valida, vista_tentativa, nodo_emisor) do
    if (n_vista_latido == vista_tentativa.num_vista
       && nodo_emisor == vista_tentativa.primario) do
      # Se confirma la vista por el nodo primario
      vista_tentativa
    else
      vista_valida
    end
  end

  # Actualiza el servidor primario por la copia
  # vista_tentativa.copia != :undefined
  defp actualizar_primario_caido(vista_tentativa, latidos) do
    # Nueva vista con copia como primario
    vista_tentativa = %{vista_tentativa |
      num_vista: vista_tentativa.num_vista + 1,
      primario: vista_tentativa.copia}

    # Comprobar nuevo nodo copia
    vista_tentativa =
      if (length(latidos) > 1) do
        # Promocion espera a copia
        %{vista_tentativa | copia: elem(Enum.at(latidos, 1), 0)}
      else
        # Copia indefinida
        IO.puts("WARNING: No hay copia")
        %{vista_tentativa | copia: :undefined}

    end

    vista_tentativa
  end

  defp actualizar_copia_caido(vista_tentativa, latidos) do
    # Nueva vista
    vista_tentativa = %{vista_tentativa |
      num_vista: vista_tentativa.num_vista + 1}

    # Comprobar nuevo nodo copia
    vista_tentativa =
      if (length(latidos) > 1) do
        # Promocion espera a copia
        %{vista_tentativa | copia: elem(Enum.at(latidos, 1), 0)}
      else
        # Copia indefinida
        %{vista_tentativa | copia: :undefined}
        IO.puts("WARNING: No hay copia")
    end

    vista_tentativa
  end

  defp actualizar_servidores(primario_caido?, copia_caido?, vista_valida,
         vista_tentativa, latidos) do
    cond do
      primario_caido? && copia_caido? ->
        IO.puts("ERROR: Primario y copia caidos")
        {vista_inicial(), vista_tentativa, latidos, false}

      primario_caido? && (vista_valida != vista_tentativa) ->
        IO.puts("ERROR: Primario caido con vista_tentativa sin confirmar")
        {vista_inicial(), vista_tentativa, latidos, false}

      true ->
        # Se comprueba si hay que promocionar servidores
        vista_tentativa = cond do
          primario_caido? -> actualizar_primario_caido(vista_tentativa, latidos)
          copia_caido? -> actualizar_copia_caido(vista_tentativa, latidos)
          true -> vista_tentativa
        end
        {vista_valida, vista_tentativa, latidos, true}
    end
  end
end
