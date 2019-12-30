Code.require_file("#{__DIR__}/cliente_gv.exs")

# Practica 5 Sistemas distribuidos
# Autores: Óscar Baselga y Alberto Calvo
# NIAs: 760077 y 760739
# Fecha: 30 de diciembre de 2019

defmodule ServidorSA do

  # estado del servidor
  defstruct vista: %ServidorGV{},
            datos: %{},
            peticiones: %{},
            automata: :nodo_tipo_espera


  @intervalo_latido 50


  @doc """
      Obtener el hash de un string Elixir
          - Necesario pasar, previamente,  a formato string Erlang
       - Devuelve entero
  """
  def hash(string_concatenado) do
    String.to_charlist(string_concatenado)
    |> :erlang.phash2
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
  @spec startService(node, node) :: pid
  def startService(nodoSA, nodo_servidor_gv) do
    NodoRemoto.esperaNodoOperativo(nodoSA, __MODULE__)

    # Poner en marcha el código del gestor de vistas
    Node.spawn(nodoSA, __MODULE__, :init_sa, [nodo_servidor_gv])
  end

  #------------------- Funciones privadas -----------------------------

  def init_sa(nodo_servidor_gv) do
    Process.register(self(), :servidor_sa)

    # Iniciar latido
    spawn(__MODULE__, :latido_periodico, [self()])

    bucle_recepcion_principal(%ServidorSA{}, nodo_servidor_gv)
  end

  def latido_periodico(servidor_sa) do
    send(servidor_sa, {:enviar_latido})
    Process.sleep(@intervalo_latido)
    latido_periodico(servidor_sa)
  end

  defp bucle_recepcion_principal(estado, nodo_servidor_gv) do
    n_estado = receive do
      {:enviar_latido} ->
        enviar_latido(nodo_servidor_gv, estado)

      {:copiar_datos, datos, peticiones, primario} ->
        copiar_datos(estado, datos, peticiones, primario)

      {:fin_espera_confirmacion} -> confirmacion_copia(estado)

      {:pedir_nueva_copia, pid} ->
        send(pid, {:nueva_copia, estado.vista.copia})
        estado

      # Solicitudes de lectura y escritura de clientes del servicio alm.
      {op, param, nodo_cliente, id} ->
        procesar_peticion(estado, op, param, nodo_cliente, id)
    end

    bucle_recepcion_principal(n_estado, nodo_servidor_gv)
  end

  #--------- Otras funciones privadas que necesiteis .......

  # -------- Funciones de peticiones de servicio almacenamiento --------

  # Ejecuta una peticion de servicio de almacenamiento devolviendo un resultado
  # a nodo_cliente.
  # Devuelve el nuevo estado del servidor
  defp procesar_peticion(estado, op, param, nodo_cliente, id) do
    n_estado =
      if estado.automata in [:primario, :esperando_inicializacion_copia,
        :esperando_confirmacion_copia] do
        n_estado =
          case op do
            :lee ->
              case estado.automata do
                # Permite lecturas en primario si no hay escritura pendiente
                n when n in [:primario, :esperando_inicializacion_copia] ->
                  valor = Map.get(estado.datos, String.to_atom(param), "")
                  send({:cliente_sa, nodo_cliente}, {:resultado, valor})
                  estado

                _ -> estado
              end

            :escribe_generico ->
              # Solo se permite escritura cuando no hay confirmaciones pendientes
              if estado.automata == :primario do
                {clave, nuevo_valor, con_hash} = param
                escribir(estado, String.to_atom(clave),
                  nuevo_valor, con_hash, nodo_cliente, id)

              else
                estado
              end
          end

    else
      send({:cliente_sa, nodo_cliente}, {:resultado, :no_soy_primario_valido})
      estado
    end

    n_estado
  end

  # Peticion de escritura con/sin hash.
  # Si con_hash escribe en estado.datos hash(antiguo_valor <> nuevo_valor) y
  # envia a nodo_cliente antiguo_valor.
  # En el caso contrario escribe nuevo_valor y envia nuevo_valor
  # Devuelve el nuevo estado del servidor
  defp escribir(estado, clave, nuevo_valor, con_hash, nodo_cliente, id) do
    n_estado =
      if con_hash do
        antiguo_valor = Map.get(estado.datos, String.to_atom(clave), "")
        valor_hash = hash(antiguo_valor <> nuevo_valor)
        n_estado = %{estado |
          datos: Map.put(estado.datos, clave, valor_hash),
          automata: :esperando_confirmacion_copia}

        # Proceso para enviar los datos y esperar confirmacion con timeout
        _pid = spawn(__MODULE__, :enviar_escritura, [n_estado, self(),
          antiguo_valor, nodo_cliente, 5])

        n_estado
    else
      if (!repetida(estado, nodo_cliente, id)) do
        n_estado = %{estado |
          datos: Map.put(estado.datos, clave, nuevo_valor),
          peticiones: Map.put(estado.peticiones, nodo_cliente, id),
          automata: :esperando_confirmacion_copia}

        # Proceso para enviar los datos y esperar confirmacion con timeout
        _pid = spawn(__MODULE__, :enviar_escritura, [n_estado, self(),
          nuevo_valor, nodo_cliente, 5])

        n_estado

      else
        send({:cliente_sa, nodo_cliente}, {:resultado, nuevo_valor})
        estado
      end

    end
    n_estado
  end


  # -------- Funciones de envio de datos y backup de copia --------

  def enviar_escritura(estado, pid_confirmacion, valor_a_devolver,
        nodo_cliente, 0) do
    send(pid_confirmacion, {:pedir_nueva_copia, self()})
    receive do
      {:nueva_copia, nodo_copia} ->
        n_estado = %{estado | vista: %{estado.vista | copia: nodo_copia}}
      enviar_escritura(n_estado, pid_confirmacion, valor_a_devolver,
        nodo_cliente, 5)
    end
  end

  # Se envia en bucle estado.datos al servidor estado.copia hasta que se recibe
  # la confirmacion. Una vez se recibe, se envia una respuesta al cliente y un
  # mensaje de confirmacion a pid_confirmacion para avanzar de estado.automata
  def enviar_escritura(estado, pid_confirmacion, valor_a_devolver,
         nodo_cliente, intentos) do
    send({:servidor_sa, estado.vista.copia}, {:copiar_datos, estado.datos,
      estado.peticiones, self()})
    receive do
      :copia_confirma ->
        send({:cliente_sa, nodo_cliente}, {:resultado, valor_a_devolver})
        send(pid_confirmacion, {:fin_espera_confirmacion})

    after 4*@intervalo_latido ->
      enviar_escritura(estado, pid_confirmacion, valor_a_devolver, nodo_cliente,
        intentos - 1)
    end
  end

  # Se envia los datos del servidor al nodo_copia hasta que se reciba
  # confirmacion. Tras recibirla, se envia confirmacion a pid_confirmacion para
  # avanzar de estado.automata
  def enviar_copia(datos, peticiones, pid_confirmacion, nodo_copia) do
    send({:servidor_sa, nodo_copia}, {:copiar_datos, datos, peticiones, self()})
    receive do
      :copia_confirma ->
        send(pid_confirmacion, {:fin_espera_confirmacion})

    after 4*@intervalo_latido ->
      enviar_copia(datos, peticiones, pid_confirmacion, nodo_copia)

    end
  end


  # Modifica el estado del servidor, actualizando los datos
  # Devuelve el nuevo estado del servidor
  defp copiar_datos(estado, datos, peticiones, primario) do
    if estado.automata == :copia || estado.automata == :proxima_copia do
      send(primario, :copia_confirma) # confirmar copia
      %{estado |
        datos: datos,
        peticiones: peticiones,
        automata: :copia}  # Actualizar datos

    else
      estado
    end
  end

  # En caso de estar esperando confirmacion de la copia, actualiza el estado.
  # Devuelve el nuevo estado del servidor
  defp confirmacion_copia(estado) do
    #IO.puts("CONFIRMACION_COPIA()")
    case estado.automata do
      :esperando_inicializacion_copia ->
        %{estado |
          # Se confirma nueva vista
          vista: %{estado.vista | num_vista: estado.vista.num_vista + 1},
          automata: :primario}

      :esperando_confirmacion_copia ->
        %{estado | automata: :primario}

      _ -> estado
    end
  end


  # -------- Funciones sobre latido y actualizacion segun su respuesta --------

  # Envia un latido al servidor_gv con estado.num_vista. Dependiendo del
  # estado.automata actualiza el estado del servidor
  # Devuelve el nuevo estado del servidor
  defp enviar_latido(nodo_servidor_gv, estado) do
    {vista, _is_ok?} = ClienteGV.latido(nodo_servidor_gv, estado.vista.num_vista)

    # Actualizacion del estado
    n_estado = case estado.automata do
      :nodo_tipo_espera -> actualizar_nodo_tipo_espera(estado, vista)
      :primario -> actualizar_primario(estado, vista)
      :esperando_inicializacion_copia -> estado
      :copia -> actualizar_copia(estado, vista)
      _ -> actualizar_generico(estado, vista)
    end
    n_estado
  end

  # Actualiza el estado del servidor primario segun la vista recibida
  defp actualizar_primario(estado, vista) do
    if vista.primario == Node.self() && vista.copia != estado.vista.copia do
      # Se ha cambiado de copia y hay que enviar los datos
      _pid = spawn(__MODULE__, :enviar_copia, [estado.datos, estado.peticiones,
        self(), vista.copia])
      %{estado |
        vista: %{vista | copia: vista.copia},
        automata: :esperando_inicializacion_copia}
    else
      actualizar_generico(estado, vista)
    end
  end

  # Actualiza el estado del servidor copia segun la vista recibida
  defp actualizar_copia(estado, vista) do
    if (vista.primario == Node.self()) do
      # He sido promocionado a primario
      _pid = spawn(__MODULE__, :enviar_copia, [estado.datos, estado.peticiones,
        self(), vista.copia])
      %{estado |
        vista: %{vista | copia: vista.copia},
        automata: :esperando_inicializacion_copia}

    else
      actualizar_generico(estado, vista)
    end
  end

  # Actualiza el estado del servidor en espera segun la vista recibida
  defp actualizar_nodo_tipo_espera(estado, vista) do
    cond do
      # Primer primario
      vista.primario == Node.self() && vista.num_vista == 1 ->
        %{estado |
          vista: %{vista | num_vista: -1},
          automata: :primario}

      # Promocion a copia
      vista.copia == Node.self() ->
          %{estado |
            vista: vista,
            automata: :proxima_copia}

      true -> actualizar_generico(estado, vista)
    end
  end

  # Actualizacion generica de los servidores del servicio de almacenamiento
  defp actualizar_generico(estado, vista) do
    n_estado =  %{estado | vista: vista}
    if (vista.primario != Node.self() && vista.copia != Node.self()) do
      # Vuele a nodo de tipo espera por decision del SGV
      %{n_estado | automata: :nodo_tipo_espera, datos: %{}}
    else
      n_estado # Se devuelve estado actualizado
    end
  end

  # -------- Otras funciones privadas --------

  defp repetida(estado, nodo_cliente, id) do
    id_antiguo = Map.get(estado.peticiones, nodo_cliente, -1)
    id <= id_antiguo
  end

end
