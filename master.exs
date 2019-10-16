# AUTORES: Alberto Calvo Rubio, Oscar Baselga Lahoz
# NIAs: 760739, 760077
# FICHERO: master.exs
# FECHA: 15/10/19
# TIEMPO:
# DESCRIPCION: modulo del master

defmodule Master do
    def listen() do
        receive do
            {pidCliente, op, lista, n} -> IO.puts("listened"); spawn fn -> atender(pidCliente, op, lista, n); IO.puts()
        end
        listen()
    end

    def atender(pidCliente, op, lista, n)
        IO.puts("Spawneado")
        #send(pidPool, {self() :request})
        #receive do
        #    {:reply, pidWorker} -> send(pidWorker, {self(), op, lista, n})
        #end
        #receive do
        #    {:resultadoWorker, resultado} -> send(pidPool, {:fin, pidWorker})
        #end
        send(pidCliente, 10)
             

    end
end