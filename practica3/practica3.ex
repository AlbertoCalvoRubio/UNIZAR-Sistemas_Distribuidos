defmodule Proxy do
    def proxy() do
        # Recibir peticion y spawnear atender
    end
    
end

defmodule Master do
    def init() do
        # ?Iniciar logica de eleccion de lider

        # Comenzar funcion master
    end

    defp master() do
        # Recibir peticion del proxy y spawn de atender

    end

    defp atender() do
        # Pedir trabajador

        # Mandar trabajar

        # Recibir respuesta
    end
end

defmodule Pool do 
    def init do
        # Creacion de workers

        # Crear "vigilantes"

        # Comenzar funcion pool
    end

    defp pool() do
        # Mantener lista de nodos, nodos activos carga de trabajo...

        # Recibir peticion y enviar mejor nodo
    end
end

defmodule Maton do

end