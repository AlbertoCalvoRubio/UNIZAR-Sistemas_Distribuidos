Code.require_file("#{__DIR__}/cliente_gv.exs")

defmodule ClienteSA do
    
    @doc """
        Poner en marcha un nodo cliente del servicio de almacenamiento
    """
    @spec start(String.t, String.t, node) :: node
    def start(host, nombre_nodo, nodo_servidor_gv) do

        nodo = NodoRemoto.start(host, nombre_nodo, __ENV__.file,__MODULE__)

        Node.spawn(nodo, __MODULE__, :init, [nodo_servidor_gv])

        nodo    
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
    def startService(nodoCA, nodo_servidor_gv) do
        NodoRemoto.esperaNodoOperativo(nodoCA, __MODULE__)
        
        # Poner en marcha el código del gestor de vistas
        Node.spawn(nodoCA, __MODULE__, :init, [nodo_servidor_gv])
   end

    @doc """
       Obtener el valor en curso de la clave
       - Devuelve cadena vacia de caracteres ("") si no existe la clave
       - Seguir intentandolo  en el resto de situaciones de fallo o error
       La especificación del interfaz de la función es la siguiente :
                            (se puede utilizar también para "dialyzer")
    """
    @spec lee( node(), String.t, Integer.t ) :: String.t
    def lee(nodo_cliente, clave, id) do
        send({:cliente_sa, nodo_cliente}, {:lee, clave, self(), id})
        IO.puts("Pido leer a #{nodo_cliente}")
        receive do
            {:resultado, valor} -> valor

            _otro -> exit("ERROR de programa : funcion lee en modulo CLienteSA")
        end
    end


    @doc """
       Escribir un valor para una clave
       - Seguir intentandolo hasta que se tenga exito
       - Devuelve valor anterior si hash y nuevo sino
       La especificación del interfaz de la función es la siguiente :
                            (se puede utilizar también para "dialyzer")
    """
    @spec escribe_generico( node(), String.t, String.t, boolean, Integer.t )
          :: String.t
    def escribe_generico(nodo_cliente, clave, nuevo_valor, con_hash, id) do
        send({:cliente_sa, nodo_cliente}, {:escribe_generico,
          {clave, nuevo_valor, con_hash}, self(), id})

        receive do
            {:resultado, valor} -> valor

            otro ->
                #:io.format "otro en ClienteSA.escribe_generico : ~p~n", [otro]

                Process.sleep 100

                exit("ERROR: funcion escribe_generico en modulo CLienteSA")
        end       
    end
     

    @doc """
       - Devuelve nuevo valor escrito
    """
    @spec escribe( node(), String.t, String.t, Integer.t ) :: String.t
    def escribe(nodo_cliente, clave, nuevo_valor, id) do
        escribe_generico(nodo_cliente, clave, nuevo_valor, false, id)
    end

    @doc """
       - Devuelve valor anterior
    """
    @spec escribe_hash( node(), String.t, String.t, Integer.t) :: String.t
    def escribe_hash(nodo_cliente, clave, nuevo_valor, id) do
        escribe_generico(nodo_cliente, clave, nuevo_valor, true, id)
    end
    

    #------------------- Funciones privadas ---------------------------------

    def init(nodo_servidor_gv) do
        Process.register(self(), :cliente_sa)

        bucle_recepcion(nodo_servidor_gv)
    end


    defp bucle_recepcion(servidor_gv) do
        receive do
            {op, param, pid, id} when (op == :lee) or (op == :escribe_generico) ->
                resultado = realizar_operacion(op, param, servidor_gv, id)
                send(pid, {:resultado, resultado})
                bucle_recepcion(servidor_gv)

            _otro -> exit("ERROR: mensaje erroneo en ClienteSA.bucle_recepcion")
        end   
    end


    defp realizar_operacion(op, param, servidor_gv, id) do
        # Obtener el primario del servicio de almacenamiento
        p = ClienteGV.primario(servidor_gv)
        
        #IO.puts "CLienteSA #{node} obtiene nod PRIMARIO #{p}"
    
        case p do
            :undefined ->  # esperamos un rato si aparece primario
                Process.sleep(ServidorGV.intervalo_latidos())
                realizar_operacion(op, param, servidor_gv, id)

            nodo_primario ->   # enviar operación a ejecutar a primario
                IO.puts("Pido #{op} a #{nodo_primario}")
                send({:servidor_sa, nodo_primario}, {op, param, Node.self(), id})
    
                # recuperar resultado
                receive do
                    {:resultado, :no_soy_primario_valido} ->
                        realizar_operacion(op, param, servidor_gv, id)

                    {:resultado, valor} ->
                      #IO.puts("Valor recibido")
                      valor

                # Sin resultado en tiempo establecido ?
                # -> se vuelve a pedir operacion al primario en curso
                after ServidorGV.intervalo_latidos() ->
                    realizar_operacion(op, param, servidor_gv, id)
                end
        end
    end

 
end
