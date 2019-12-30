Code.require_file("#{__DIR__}/nodo_remoto.exs")
Code.require_file("#{__DIR__}/servidor_gv.exs")
Code.require_file("#{__DIR__}/cliente_gv.exs")
Code.require_file("#{__DIR__}/servidor_sa.exs")
Code.require_file("#{__DIR__}/cliente_sa.exs")

#Poner en marcha el servicio de tests unitarios con tiempo de vida limitada
# seed: 0 para que la ejecucion de tests no tenga orden aleatorio
ExUnit.start([timeout: 20000, seed: 0, exclude: [:deshabilitado]]) # milisegundos

defmodule  ServicioAlmacenamientoTest do

    use ExUnit.Case

    # @moduletag timeout 100  para timeouts de todos lo test de este modulo

    @maquinas ["127.0.0.1", "127.0.0.1", "127.0.0.1"]
    # @maquinas ["155.210.154.192", "155.210.154.193", "155.210.154.194"]

    #@latidos_fallidos 4

    #@intervalo_latido 50


    #setup_all do


    #@tag :deshabilitado
    test "Test 1: solo_arranque y parada" do
        IO.puts("Test: Solo arranque y parada ...")


        # Poner en marcha nodos, clientes, servidores alm., en @maquinas
        mapNodos = startServidores(["ca1"], ["sa1"], @maquinas)

        Process.sleep(500)

        # Parar todos los nodos y epmds
        stopServidores(mapNodos, @maquinas)

        IO.puts(" ... Superado")
    end

    #@tag :deshabilitado
    test "Test 2: Algunas escrituras" do
        #:io.format "Pids de nodo MAESTRO ~p: principal = ~p~n", [node, self]

        #Process.flag(:trap_exit, true)

        # Para que funcione bien la función  ClienteGV.obten_vista
        Process.register(self(), :servidor_sa)

        # Arrancar nodos : 1 GV, 3 servidores y 1 cliente de almacenamiento
        mapa_nodos = startServidores(["ca1"], ["sa1", "sa2", "sa3"], @maquinas)

        # Espera configuracion y relacion entre nodos
        Process.sleep(1200)

        IO.puts("Test: Comprobar escritura con primario, copia y espera ...")

        # Comprobar primeros nodos primario y copia
        {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
        assert p == mapa_nodos.sa1
        assert c == mapa_nodos.sa2


        ClienteSA.escribe(mapa_nodos.ca1, "a", "aa", 0)
        ClienteSA.escribe(mapa_nodos.ca1, "b", "bb", 1)
        ClienteSA.escribe(mapa_nodos.ca1, "c", "cc", 2)
        IO.puts("Escrituras hechas")
        comprobar(mapa_nodos.ca1, "a", "aa", 3)
        comprobar(mapa_nodos.ca1, "b", "bb", 4)
        comprobar(mapa_nodos.ca1, "c", "cc", 5)

        IO.puts(" ... Superado")

        IO.puts("Test: Comprobar escritura despues de fallo de nodo copia ...")

        # Provocar fallo de no do copia y seguido realizar una escritura
        {%{copia: nodo_copia},_} = ClienteGV.obten_vista(mapa_nodos.gv)
        NodoRemoto.stop(nodo_copia) # Provocar parada nodo copia

        Process.sleep(700) # esperar a reconfiguracion de servidores

        ClienteSA.escribe(mapa_nodos.ca1, "a", "aaa", 3)
        comprobar(mapa_nodos.ca1, "a", "aaa", 4)

        # Comprobar los nuevo nodos primario y copia
        {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
        assert p == mapa_nodos.sa1
        assert c == mapa_nodos.sa3

        IO.puts(" ... Superado")

        # Parar todos los nodos y epmds
        stopServidores(mapa_nodos, @maquinas)
    end

    #@tag :deshabilitado
    test "Test 3 : Mismos valores concurrentes" do
        IO.puts("Test: Escrituras mismos valores clientes concurrentes ...")

        # Para que funcione bien la función  ClienteGV.obten_vista
        Process.register(self(), :servidor_sa)

        # Arrancar nodos : 1 GV, 3 servidores y 3 cliente de almacenamiento
        mapa_nodos = startServidores(["ca1", "ca2", "ca3"],
                                     ["sa1", "sa2", "sa3"],
                                     @maquinas)

        # Espera configuracion y relacion entre nodos
        Process.sleep(1500)

        # Comprobar primeros nodos primario y copia
        {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
        assert p == mapa_nodos.sa1
        assert c == mapa_nodos.sa2

        # Escritura concurrente de mismas 2 claves, pero valores diferentes
        # Posteriormente comprobar que estan igual en primario y copia
        escritura_concurrente(mapa_nodos, 0)

        Process.sleep(200)

        #Obtener valor de las clave "0" y "1" con el primer primario
         valor1primario = ClienteSA.lee(mapa_nodos.ca1, "0", 1)
         valor2primario = ClienteSA.lee(mapa_nodos.ca3, "1", 1)

         # Forzar parada de primario
         NodoRemoto.stop(ClienteGV.primario(mapa_nodos.gv))

        # Esperar detección fallo y reconfiguración copia a primario
        Process.sleep(700)

        # Obtener valor de clave "0" y "1" con segundo primario (copia anterior)
         valor1copia = ClienteSA.lee(mapa_nodos.ca3, "0", 2)
         valor2copia = ClienteSA.lee(mapa_nodos.ca2, "1", 1)

        IO.puts ("valor1primario = #{valor1primario}, valor1copia = #{valor1copia}")
        IO.puts("valor2primario = #{valor2primario}, valor2copia = #{valor2copia}")
        # Verificar valores obtenidos con primario y copia inicial
        assert valor1primario == valor1copia
        assert valor2primario == valor2copia

        # Parar todos los nodos y epmds
        stopServidores(mapa_nodos, @maquinas)

         IO.puts(" ... Superado")
    end


    # Test 4 : Escrituras concurrentes y comprobación de consistencia
    #         tras caída de primario y copia.
    #         Se puede gestionar con cuatro nodos o con el primario rearrancado.
    #@tag :deshabilitado
    test "Test 4 : Escrituras concurrentes y comprobacion de concurrencia" do
        IO.puts("Test 4: Escrituras concurrentes y comprobacion de concurrencia ...")

        # Para que funcione bien la función  ClienteGV.obten_vista
        Process.register(self(), :servidor_sa)

        # Arrancar nodos : 1 GV, 4 servidores y 4 cliente de almacenamiento
        mapa_nodos = startServidores(["ca1", "ca2", "ca3", "ca4"],
            ["sa1", "sa2", "sa3", "sa4"],
            @maquinas)

        # Espera configuracion y relacion entre nodos
        Process.sleep(200)

        # Comprobar primeros nodos primario y copia
        {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
        assert p == mapa_nodos.sa1
        assert c == mapa_nodos.sa2

        # Escritura concurrente de mismas 2 claves, pero valores diferentes
        # Posteriormente comprobar que estan igual en primario y copia
        escritura_concurrente(mapa_nodos, 0)

        Process.sleep(200)

        #Obtener valor de las clave "0" y "1" con el primer primario
        valor1primario = ClienteSA.lee(mapa_nodos.ca1, "0", 1)
        valor2primario = ClienteSA.lee(mapa_nodos.ca3, "1", 1)

        # Forzar parada de primario
        NodoRemoto.stop(ClienteGV.primario(mapa_nodos.gv))

        # Esperar detección fallo y reconfiguración copia a primario
        Process.sleep(700)

        # Obtener valor de clave "0" y "1" con segundo primario (copia anterior)
        valor1copia = ClienteSA.lee(mapa_nodos.ca3, "0", 2)
        valor2copia = ClienteSA.lee(mapa_nodos.ca2, "1", 1)

        IO.puts("valor1primario = #{valor1primario}, valor1copia = #{valor1copia}")
        IO.puts("valor2primario = #{valor2primario}, valor2copia = #{valor2copia}")

        # Verificar valores obtenidos con primario y copia inicial
        assert valor1primario == valor1copia
        assert valor2primario == valor2copia

        # Forzar parada del segundo primario
        NodoRemoto.stop(ClienteGV.primario(mapa_nodos.gv))

        # Esperar detección fallo y reconfiguración copia a primario
        Process.sleep(700)

        # Obtener valor de clave "0" y "1" con segundo primario (copia anterior)
        valor1copia = ClienteSA.lee(mapa_nodos.ca2, "0", 2)
        valor2copia = ClienteSA.lee(mapa_nodos.ca4, "1", 1)

        IO.puts "valor1primario = #{valor1primario}, valor1copia = #{valor1copia}"
        IO.puts("valor2primario = #{valor2primario}, valor2copia = #{valor2copia}")
        # Verificar valores obtenidos con primario y copia inicial
        assert valor1primario == valor1copia
        assert valor2primario == valor2copia

        # Parar todos los nodos y epmds
        stopServidores(mapa_nodos, @maquinas)

        IO.puts(" ... Superado")
    end

    # Test 5 : Petición de escritura inmediatamente después de la caída de nodo
    #         copia (con uno en espera que le reemplace).
    #@tag :deshabilitado
    test "Test 5: Escritura inmediata tras caida de copia" do
        IO.puts("Test 5: Escritura inmediata tras caida de copia ...")

        # Para que funcione bien la función  ClienteGV.obten_vista
        Process.register(self(), :servidor_sa)

        # Arrancar nodos : 1 GV, 3 servidores y 3 cliente de almacenamiento
        mapa_nodos = startServidores(["ca1", "ca2"],
            ["sa1", "sa2", "sa3", "sa4"],
            @maquinas)

        # Espera configuracion y relacion entre nodos
        Process.sleep(200)

        # Comprobar primeros nodos primario y copia
        {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
        assert p == mapa_nodos.sa1
        assert c == mapa_nodos.sa2

        # Forzar parada de la copia
        NodoRemoto.stop(mapa_nodos.sa2)

        # Escritura inmediatamente despues
        ClienteSA.escribe(mapa_nodos.ca1, "a", "aa", 0)

        Process.sleep(1000)

        # Lectura de la escritura anterior en el primer primario
        comprobar(mapa_nodos.ca1, "a", "aa", 1)
        valorPrimario = ClienteSA.lee(mapa_nodos.ca1, "a", 2)

        # Forzar parada del primer primario
        NodoRemoto.stop(ClienteGV.primario(mapa_nodos.gv))

        Process.sleep(1000)

        # Lectura de la escritura anterior en el segundo primario(segunda copia)
        comprobar(mapa_nodos.ca2, "a", "aa", 0)
        valorCopia = ClienteSA.lee(mapa_nodos.ca2, "a", 1)

        # Comprobar que se ha propagado la escritura entre el primer primario
        # y la segunda copia
        assert valorPrimario == valorCopia

        # Parar todos los nodos y epmds
        stopServidores(mapa_nodos, @maquinas)

        IO.puts(" ... Superado")

    end

    # Test 6 : Petición de escritura duplicada por perdida de respuesta
    #         (modificación realizada en BD), con primario y copia.
    #@tag :deshabilitado
    test "Test 6: Escritura duplicada" do
        IO.puts("Test 6: Escritura duplicada ...")

        # Para que funcione bien la función  ClienteGV.obten_vista
        Process.register(self(), :servidor_sa)

        # Arrancar nodos : 1 GV, 3 servidores y 2 cliente de almacenamiento
        mapa_nodos = startServidores(["ca1", "ca2"],
            ["sa1", "sa2", "sa3"],
            @maquinas)

        # Espera configuracion y relacion entre nodos
        Process.sleep(200)

        # Comprobar primeros nodos primario y copia
        {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
        assert p == mapa_nodos.sa1
        assert c == mapa_nodos.sa2

        # Cliente 1 escribe
        ClienteSA.escribe(mapa_nodos.ca1, "a", "aa", 0)

        # Cliente 2 escribe
        ClienteSA.escribe(mapa_nodos.ca2, "a", "aaaaa", 0)

        # Cliente 1 repite la misma escritura simulando que no le ha llegado el
        # resultado
        ClienteSA.escribe(mapa_nodos.ca1, "a", "aa", 0)

        # Se comprueba que se ha detectado la escritura repetida y se ha
        # mantenido la ultima escritura (cliente 2)
        comprobar(mapa_nodos.ca2, "a", "aaaaa", 1)

        # Parar todos los nodos y epmds
        stopServidores(mapa_nodos, @maquinas)

        IO.puts(" ... Superado")


    end

    # Test 7 : Comprobación de que un antiguo primario no debería servir
    #         operaciones de lectura.
    #@tag :deshabilitado
    test "Test 7: Antiguo primario no responde lecturas" do
        IO.puts("Test 7: Antiguo primario no responde lecturas ...")

        # Para que funcione bien la función  ClienteGV.obten_vista
        Process.register(self(), :servidor_sa)

        # Arrancar nodos : 1 GV, 3 servidores y 2 cliente de almacenamiento
        mapa_nodos = startServidores(["ca1", "ca2"],
            ["sa1", "sa2", "sa3"],
            @maquinas)

        # Espera configuracion y relacion entre nodos
        Process.sleep(200)

        # Comprobar primeros nodos primario y copia
        {%{primario: p, copia: c}, _ok} = ClienteGV.obten_vista(mapa_nodos.gv)
        assert p == mapa_nodos.sa1
        assert c == mapa_nodos.sa2

        clave = "a"

        # Cliente 1 escribe
        ClienteSA.escribe(mapa_nodos.ca1, clave, "aa", 0)

        antiguo_primario = ClienteGV.primario(mapa_nodos.gv)

        # Simular caida del primario
        send({:servidor_gv, mapa_nodos.gv}, {:latido, 0, antiguo_primario})

        # Tiempo para configuracion
        Process.sleep(300)

        spawn(__MODULE__, :antiguo_no_responde, [antiguo_primario, clave])

        # Parar todos los nodos y epmds
        stopServidores(mapa_nodos, @maquinas)

        IO.puts(" ... Superado")


    end



        # ------------------ FUNCIONES DE APOYO A TESTS ------------------------

    defp startServidores(clientes, serv_alm, maquinas) do
        tiempo_antes = :os.system_time(:milli_seconds)

        # Poner en marcha gestor de vistas y clientes almacenamiento
        sv = ServidorGV.startNodo("sv", "127.0.0.1")
            # Mapa con nodos cliente de almacenamiento
        clientesAlm = for c <- clientes, into: %{} do
                            {String.to_atom(c),
                            ClienteSA.startNodo(c, "127.0.0.1")}
                        end
        ServidorGV.startService(sv)
        for { _, n} <- clientesAlm, do: ClienteSA.startService(n, sv)

        # Mapa con nodos servidores almacenamiento
        servAlm = for {s, m} <-  Enum.zip(serv_alm, maquinas), into: %{} do
                      {String.to_atom(s),
                       ServidorSA.startNodo(s, m)}
                  end

        # Poner en marcha servicios de cada nodo servidor de almacenamiento
        for { _, n} <- servAlm do
            ServidorSA.startService(n, sv)
            #Process.sleep(60)
        end

        #Tiempo de puesta en marcha de nodos
        t_total = :os.system_time(:milli_seconds) - tiempo_antes
        IO.puts("Tiempo puesta en marcha de nodos  : #{t_total}")

        %{gv: sv} |> Map.merge(clientesAlm) |> Map.merge(servAlm)
    end

    defp stopServidores(nodos, maquinas) do
        IO.puts "Finalmente eliminamos nodos"

        # Primero el gestor de vistas para no tener errores por fallo de
        # servidores de almacenamiento
        { %{ gv: nodoGV}, restoNodos } = Map.split(nodos, [:gv])
        IO.inspect nodoGV, label: "nodo GV :"
        NodoRemoto.stop(nodoGV)
        IO.puts "UNo"
        Enum.each(restoNodos, fn ({ _ , nodo}) -> NodoRemoto.stop(nodo) end)
        IO.puts "DOS"
        # Eliminar epmd en cada maquina con nodos Elixir
        Enum.each(maquinas, fn(m) -> NodoRemoto.killEpmd(m) end)
    end

    defp comprobar(nodo_cliente, clave, valor_a_comprobar, id) do
        valor_en_almacen = ClienteSA.lee(nodo_cliente, clave, id)

        assert valor_en_almacen == valor_a_comprobar
    end

    def siguiente_valor(previo, actual) do
        ServidorSA.hash(previo <> actual) |> Integer.to_string
    end


    # Ejecutar durante un tiempo una escritura continuada de 3 clientes sobre
    # las mismas 2 claves pero con 3 valores diferentes de forma concurrente
    def escritura_concurrente(mapa_nodos, id) do
        aleat1 = :rand.uniform(1000)
        pid1 =spawn(__MODULE__, :bucle_infinito, [mapa_nodos.ca1, aleat1, id])
        aleat2 = :rand.uniform(1000)
        pid2 =spawn(__MODULE__, :bucle_infinito, [mapa_nodos.ca2, aleat2, id])
        aleat3 = :rand.uniform(1000)
        pid3 =spawn(__MODULE__, :bucle_infinito, [mapa_nodos.ca3, aleat3, id])

        Process.sleep(2000)

        Process.exit(pid1, :kill)
        Process.exit(pid2, :kill)
        Process.exit(pid3, :kill)
    end

    def bucle_infinito(nodo_cliente, aleat, id) do
        clave = Integer.to_string(rem(aleat, 2)) # solo claves "0" y "1"
        valor = Integer.to_string(aleat)
        miliseg = :rand.uniform(200)

        Process.sleep(miliseg)

        #:io.format "Nodo ~p, escribe clave = ~p, valor = ~p, sleep = ~p~n",
        #            [Node.self(), clave, valor, miliseg]

        ClienteSA.escribe(nodo_cliente, clave, valor, id)

        bucle_infinito(nodo_cliente, aleat, id)
    end

    def antiguo_no_responde(antiguo_primario, clave) do
       Process.register(self(), :cliente_sa)
       # Peticion de lectura a antiguo primario
       send({:servidor_sa, antiguo_primario}, {:lee, clave, Node.self(), 0})

       resultado = receive do
           {:resultado, valor} -> valor
       end

       assert resultado == :no_soy_primario_valido

    end
end

