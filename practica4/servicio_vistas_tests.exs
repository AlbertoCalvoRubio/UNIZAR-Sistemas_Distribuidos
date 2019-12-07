# Compilar y cargar ficheros con modulos necesarios
Code.require_file("nodo_remoto.exs", __DIR__)
Code.require_file("servidor_gv.exs", __DIR__)
Code.require_file("cliente_gv.exs", __DIR__)

# Poner en marcha el servicio de tests unitarios con :
# timeout : ajuste de tiempo máximo de ejecución de todos los tests, en miliseg.
# seed: 0 , para que la ejecucion de tests no tenga orden aleatorio
# exclusion de ejecución de aquellos tests que tengan el tag :deshabilitado
ExUnit.start(timeout: 10000, seed: 0, exclude: [:deshabilitado])

defmodule GestorVistasTest do
  use ExUnit.Case

  # @moduletag timeout 100  para timeouts de todos lo test de este modulo

  # Preparación de contexto de tests de integración
  # Para gestionar nodos y maquinas
  setup_all do
    # Poner en marcha los servidores, obtener nodos
    # maquinas = ["localhost.localhost", "155.210.154.206", 
    #            "155.210.154.207", "155.210.154.208"] 
    maquinas = ["localhost.localhost"]
    # devuelve una mapa de nodos del servidor y clientes
    nodos = startServidores(maquinas)

    on_exit(fn ->
      # eliminar_nodos Elixir y epmds en maquinas
      # stopServidores(nodos, maquinas)
      stopServidores(nodos, maquinas)
    end)

    {:ok, nodos}
  end

  # Test 1 : No deberia haber primario
  # @tag :deshabilitado
  test "No deberia haber primario", %{c1: c1} do
    IO.puts("Test 1: No deberia haber primario ...")

    p = ClienteGV.primario(c1)

    assert p == :undefined

    IO.puts(" ... Superado")
  end

  # Test 2 : primer primario
  # @tag :deshabilitado
  test "Primer primario", %{c1: c} do
    IO.puts("Test 2: Primer primario ...")

    primer_primario(c, ServidorGV.latidos_fallidos() * 2)
    comprobar_tentativa(c, c, :undefined, 1)

    IO.puts(" ... Superado")
  end

  # Test 3 : primer nodo copia
  # @tag :deshabilitado
  test "Primer nodo copia", %{c1: c1, c2: c2} do
    IO.puts("Test 3: Primer nodo copia ...")

    # Solo interesa vista tentativa
    {vista, _} = ClienteGV.latido(c1, -1)
    primer_nodo_copia(c1, c2, ServidorGV.latidos_fallidos() * 2)

    # validamos nueva vista por estar completa
    ClienteGV.latido(c1, vista.num_vista + 1)

    comprobar_valida(c1, c1, c2, vista.num_vista + 1)

    IO.puts(" ... Superado")
  end

  ## Test 4 : Después, Copia (C2) toma el relevo si Primario (C1) falla.
  # @tag :deshabilitado
  test "Copia releva primario", %{c2: c2} do
    IO.puts("Test4 : copia toma relevo si primario falla ...")

    {vista, _} = ClienteGV.latido(c2, 2)

    copia_releva_primario(c2,vista.num_vista, ServidorGV.latidos_fallidos() * 2)
    
    comprobar_tentativa(c2, c2, :undefined, vista.num_vista + 1)

    IO.puts(" ... Superado")
  end

  ## Test 5 : Nodo rearrancado (C1) se convierte en copia.
  # @tag :deshabilitado
  test "Servidor rearrancado se conviert en copia", %{c1: c1, c2: c2} do
    IO.puts("Test 5: Servidor rearrancado se convierte en copia ...")

    # vista tentativa
    {vista, _} = ClienteGV.latido(c2, 2)
    servidor_rearranca_a_copia(c1, c2, 2, ServidorGV.latidos_fallidos() * 2)

    # validamos nueva vista por estar DE NUEVO completa
    # vista valida debería ser 4
    ClienteGV.latido(c2, vista.num_vista + 1)

    comprobar_valida(c2, c2, c1, vista.num_vista + 1)

    IO.puts(" ... Superado")
  end

  ## Test 6 : C3 como nuevo nodo (en espera), después C2 cae como primario.
  ##          Resultado : copia (C1) pasa a primario y C3 pasa a nodo copia
  # @tag :deshabilitado
  test "Servidor en espera se convierte en copia", %{c1: c1, c3: c3} do
    IO.puts("Test 6: Servidor en espera se convierte en copia ...")

    # nuevo servidor en espera
    ClienteGV.latido(c3, 0)
    # vista tentativa
    {vista, _} = ClienteGV.latido(c1, 4)
    espera_pasa_a_copia(c1, c3, 4, ServidorGV.latidos_fallidos() * 2)

    # validamos nueva vista por estar DE NUEVO completa
    # vista valida debería ser 5
    ClienteGV.latido(c1, vista.num_vista + 1)

    comprobar_valida(c1, c1, c3, vista.num_vista + 1)

    IO.puts(" ... Superado")
  end

  ## Test 7 : Primario rearrancado (C2) tratado como caido, debe considerarlo
  ## caido aunque envie latido, y es convertido en nodo en espera.
  # @tag :deshabilitado
  test "Primario rearrancado tratado como caido", %{c1: c1, c3: c3} do
    IO.puts("Test 7: Primario rearrancado tratado como caido ...")

    # cae y recupera c1, pasa de primario a  servidor en espera
    ClienteGV.latido(c1, 0)
    # vista tentativa
    {vista, _} = ClienteGV.latido(c1, 5)
    primario_rearrancado(c1, c3, 5, ServidorGV.latidos_fallidos() * 2)
    
    comprobar_tentativa(c3, c3, c1, vista.num_vista)
  end

  
  ## Test 8 : Servidor de vistas espera a que primario confirme vista
  ##          pero este no lo hace.
  ##          Poner C3 como Primario, C1 como Copia, C2 para comprobar
  ##          - C3 no confirma vista en que es primario,
  ##          - Cae, pero C1 no es promocionado porque C3 no confimo !
  # primario_no_confirma_vista(C1, C2, C3),
  # @tag :deshabilitado
  test "Servidor de vistas espera a que primario confirme", %{c3: c3, c1: c1,
    c2: c2} do
    IO.puts("Test 8: Servidor de vistas espera a que primario confirme ...")

    # Primario cae sin confirmar
    primario_no_confirma_vista(c3, 0, ServidorGV.latidos_fallidos() * 2)

    comprobar_tentativa(c2, :undefined, :undefined, 0)

    IO.puts(" ... Superado")
  end

  
  ## Test 9 : Si anteriores servidores caen (Primario  y Copia),
  ##       un nuevo servidor sin inicializar no puede convertirse en primario.
  # sin_inicializar_no(C1, C2, C3),
  test "Sin inicializar no", %{c3: c3, c1: c1, c2: c2} do
    IO.puts("Test 9: Sin inicializar no ...")

    # c2 manda latidos pero no debe convertirse en lider ni copia
    sin_inicializar(c2, 0, ServidorGV.latidos_fallidos() * 2)

    comprobar_tentativa(c2, :undefined, :undefined, 0)

    IO.puts(" ... Superado")
  end


  
  # ------------------ FUNCIONES DE APOYO A TESTS ------------------------

  ##
  defp startServidores(maquinas) do
    tiempo_antes = :os.system_time(:milli_seconds)
    # Poner en marcha nodos servidor gestor de vistas y clientes
    # startNodos(%{tipoNodo: %{maquina: list(nombres)}})
    numMaquinas = length(maquinas)
    sv = ServidorGV.startNodo("sv", Enum.at(maquinas, 0))

    clientes =
      for i <- 1..3 do
        # solo una máquina : la máquina local
        if numMaquinas == 4 do
          ClienteGV.startNodo(
            "c" <> Integer.to_string(i),
            Enum.at(maquinas, i)
          )
        else
          ClienteGV.startNodo(
            "c" <> Integer.to_string(i),
            Enum.at(maquinas, 0)
          )
        end
      end

    # Poner en marcha servicios de cada uno
    # startServices(%{tipo: [nodos]})
    ServidorGV.startService(sv)
    c1 = ClienteGV.startService(Enum.at(clientes, 0), sv)
    c2 = ClienteGV.startService(Enum.at(clientes, 1), sv)
    c3 = ClienteGV.startService(Enum.at(clientes, 2), sv)

    # Tiempo de puesta en marcha de nodos
    t_total = :os.system_time(:milli_seconds) - tiempo_antes
    IO.puts("Tiempo puesta en marcha de nodos  : #{t_total}")

    [sv: sv, c1: c1, c2: c2, c3: c3]
  end

  ##
  defp stopServidores(servidores, maquinas) do
    IO.puts("Finalmente eliminamos nodos")
    Enum.each(servidores, fn {_, nodo} -> NodoRemoto.stop(nodo) end)

    # Eliminar epmd en cada maquina con nodos Elixir                            
    Enum.each(maquinas, fn m -> NodoRemoto.killEpmd(m) end)
  end

  ##
  defp primer_primario(_c, 0), do: :fin

  defp primer_primario(c, x) do
    {vista, _} = ClienteGV.latido(c, 0)

    if vista.primario != c do
      Process.sleep(ServidorGV.intervalo_latidos())
      primer_primario(c, x - 1)
    end
  end

  ##
  defp primer_nodo_copia(_c1, _c2, 0), do: :fin

  defp primer_nodo_copia(c1, c2, x) do
    # el primario : != 0 para no dar por nuevo y < 0 PARA NO VALIDAR !!!
    ClienteGV.latido(c1, -1)
    {vista, _} = ClienteGV.latido(c2, 0)

    if vista.copia != c2 do
      Process.sleep(ServidorGV.intervalo_latidos())
      primer_nodo_copia(c1, c2, x - 1)
    end
  end

  ##
  def copia_releva_primario(_, _num_vista_inicial, 0), do: :fin

  def copia_releva_primario(c2, num_vista_inicial, x) do
    {vista, _} = ClienteGV.latido(c2, num_vista_inicial)

    if vista.primario != c2 or vista.copia != :undefined do
      Process.sleep(ServidorGV.intervalo_latidos())
      copia_releva_primario(c2, num_vista_inicial, x - 1)
    end
  end

  ##
  defp servidor_rearranca_a_copia(_c1, _c2, _num_vista_tentativa, 0), do: :fin

  defp servidor_rearranca_a_copia(c1, c2, num_vista_tentativa, x) do
    ClienteGV.latido(c1, 0)
    {vista, _} = ClienteGV.latido(c2, num_vista_tentativa)

    if vista.copia != c1 do
      Process.sleep(ServidorGV.intervalo_latidos())
      servidor_rearranca_a_copia(c1, c2, num_vista_tentativa, x - 1)
    end
  end

  ##
  defp espera_pasa_a_copia(_c1, _c3, _num_vista_tentativa, 0), do: :fin

  defp espera_pasa_a_copia(c1, c3, num_vista_tentativa, x) do
    ClienteGV.latido(c3, num_vista_tentativa)
    {vista, _} = ClienteGV.latido(c1, num_vista_tentativa)

    if vista.primario != c1 or vista.copia != c3 do
      Process.sleep(ServidorGV.intervalo_latidos())
      espera_pasa_a_copia(c1, c3, num_vista_tentativa, x - 1)
    end
  end

  ##
  defp primario_rearrancado(_c1, _c3, _num_vista_tentativa, 0), do: :fin

  defp primario_rearrancado(c1, c3, num_vista_tentativa, x) do
    ClienteGV.latido(c1, num_vista_tentativa)
    {vista, _} = ClienteGV.latido(c3, num_vista_tentativa)

    if vista.primario != c3 do
      Process.sleep(ServidorGV.intervalo_latidos())
      primario_rearrancado(c1, c3, num_vista_tentativa, x - 1)
    end
  end

  ##
  defp primario_no_confirma_vista(_c3, _num_vista, 0), do: :fin

  defp primario_no_confirma_vista(c3, num_vista, x) do
    {vista, _} = ClienteGV.latido(c3, num_vista)

    if (vista.primario != :undefined || vista.copia != :undefined) do
      primario_no_confirma_vista(c3, num_vista, x-1)
      Process.sleep(ServidorGV.intervalo_latidos())
    end
  end

  ##
  defp sin_inicializar(_c2, _num_vista, 0), do: :fin

  defp sin_inicializar(c2, num_vista, x) do
    {vista, _} = ClienteGV.latido(c2, num_vista)

    if (vista.primario != :undefined || vista.copia != :undefined) do
      primario_no_confirma_vista(c2, num_vista, x-1)
      Process.sleep(ServidorGV.intervalo_latidos())
    end
  end
  
  defp comprobar_tentativa(nodo_cliente, nodo_primario, nodo_copia, n_vista) do
    # Solo interesa vista tentativa
    {vista, _} = ClienteGV.latido(nodo_cliente, -1)

    comprobar(nodo_primario, nodo_copia, n_vista, vista)
  end

  defp comprobar_valida(nodo_cliente, nodo_primario, nodo_copia, n_vista) do
    {vista, _} = ClienteGV.obten_vista(nodo_cliente)

    comprobar(nodo_primario, nodo_copia, n_vista, vista)

    assert ClienteGV.primario(nodo_cliente) == nodo_primario
  end

  defp comprobar(nodo_primario, nodo_copia, n_vista, vista) do
    assert vista.primario == nodo_primario

    assert vista.copia == nodo_copia

    assert vista.num_vista == n_vista
  end
end
