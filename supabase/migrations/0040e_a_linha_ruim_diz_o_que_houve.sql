-- 0040e · A linha ruim diz o que houve.
--
-- Dois defeitos, achados pelo teste 25, e o segundo só existia porque o
-- primeiro estava escondido.
--
-- **1. O join estava errado.** `importar_historico` procurava
-- `profissionais.profissional_id` — coluna que não existe; o que ela queria era
-- `pacientes.profissional_id`, que já estava ali na mesma consulta. Erro de
-- digitação, do tipo que o compilador pegaria em qualquer linguagem e que em
-- plpgsql só aparece quando a linha roda.
--
-- **2. O `exception when others` engolia o motivo.** Toda linha que falhasse,
-- por qualquer razão, voltava como "não consegui ler esta linha" — e foi
-- exatamente isso que a importação inteira respondeu enquanto o defeito 1
-- estava lá. Uma mensagem que serve para tudo não serve para nada: quem colou
-- a planilha não sabe se errou a data, se o paciente não é dela, ou se o
-- sistema está quebrado.
--
-- Agora o motivo carrega o que o banco disse, cortado em 120 caracteres. É o
-- mesmo princípio da B14 ("erro é por linha, na fronteira com dado de fora"),
-- levado até o fim: erro por linha **e com o motivo daquela linha**.
--
-- **Regra que fica:** captura genérica que não repassa o `sqlerrm` transforma
-- defeito em mistério — e o mistério dura até alguém escrever um teste.

create or replace function public.importar_historico(p_linhas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  prof uuid;
  linha jsonb;
  n int := 0;
  n_pulou int := 0;
  erros jsonb := '[]'::jsonb;
  i int := 0;
  pac uuid;
  ini timestamptz;
  f timestamptz;
  est text;
  val numeric;
begin
  if c is null then raise exception 'sem conta'; end if;

  for linha in select * from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) loop
    i := i + 1;
    begin
      pac := (linha->>'paciente_id')::uuid;
      ini := (linha->>'inicio')::timestamptz;
      f   := coalesce((linha->>'fim')::timestamptz, ini + interval '50 minutes');
      est := coalesce(linha->>'estado', 'realizada');
      val := coalesce((linha->>'valor')::numeric, 0);

      select pa.profissional_id into prof
        from public.pacientes pa
       where pa.id = pac and pa.conta_id = c;

      if prof is null then
        erros := erros || jsonb_build_object('linha', i, 'motivo', 'paciente não é desta conta');
        continue;
      end if;

      if est not in ('realizada', 'falta', 'cancelada_cedo', 'cancelada_tarde') then
        erros := erros || jsonb_build_object('linha', i, 'motivo', 'estado não é um desfecho');
        continue;
      end if;

      if ini >= now() then
        erros := erros || jsonb_build_object('linha', i, 'motivo', 'histórico é passado');
        continue;
      end if;

      if exists (
        select 1 from public.sessoes s
         where s.paciente_id = pac and s.inicio = ini
      ) then
        n_pulou := n_pulou + 1;
        continue;
      end if;

      insert into public.sessoes
        (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor)
      values (c, prof, pac, ini, f, 'importada', est, val);

      n := n + 1;
    exception when others then
      erros := erros || jsonb_build_object('linha', i, 'motivo', left(sqlerrm, 120));
    end;
  end loop;

  return jsonb_build_object('importadas', n, 'repetidas', n_pulou, 'erros', erros);
end;
$$;

revoke execute on function public.importar_historico(jsonb) from public, anon;
grant execute on function public.importar_historico(jsonb) to authenticated;

comment on function public.importar_historico(jsonb) is
  'Sessoes que ja aconteceram, com origem importada. Memoria, nao dinheiro. Erro e por linha e carrega o motivo daquela linha.';
