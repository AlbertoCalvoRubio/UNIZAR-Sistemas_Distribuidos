# AUTOR: Rafael Tolosana Calasanz
 # FICHERO: repositorio.exs
 # FECHA: 17 de octubre de 2019
 # TIEMPO: 1 hora
 # DESCRIPCI'ON:  	Implementa un repositorio para gestionar el enunciado de un trabajo de asignatura.
 # 				El enunciado tiene tres partes: resumen, parte principal y descripci'on de la entrega.
 #				El repositorio consta de un servidor que proporciona acceso individual a cada parte del enunciado,
 #				bien en lectura o bien en escritura				
 
defmodule Repositorio do
	def init do
		repo_server({"", "", ""})
	end
	defp repo_server({resumen, principal, entrega}) do
		{n_resumen, n_principal, n_entrega} = receive do
			{:update_resumen, c_pid, descripcion} -> send(c_pid, {:reply, :ok}); {descripcion, principal, entrega}
			{:update_principal, c_pid, descripcion} -> send(c_pid, {:reply, :ok}); {resumen, descripcion, entrega}
			{:update_entrega, c_pid, descripcion} -> send(c_pid, {:reply, :ok}); {resumen, principal, descripcion}
			{:read_resumen, c_pid} -> send(c_pid, {:reply, resumen}); {resumen, principal, entrega}
			{:read_principal, c_pid} -> send(c_pid, {:reply, principal}); {resumen, principal, entrega}
			{:read_entrega, c_pid} -> send(c_pid, {:reply, entrega}); {resumen, principal, entrega}
		end
		repo_server({n_resumen, n_principal, n_entrega})
	end
end