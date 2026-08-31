-- 0020 · A quinta família.
--
-- A B11 precisa avisar sobre uma cobrança, e a lista de templates da 0017 é
-- fechada de propósito: template novo é migração, não string solta no app.
-- Então abrir espaço para ele é exatamente isto — uma linha de migração,
-- revisável, versionada, que aparece no diff.
--
-- O texto em si mora em `lib/mensageria/templates.ts`, e tem um portão que não
-- é técnico: é rascunho até uma psicóloga lê-lo. O banco só reserva o nome.

alter table public.mensagens drop constraint if exists mensagens_template_check;

alter table public.mensagens add constraint mensagens_template_check
  check (template in (
    'oferta_de_vaga',
    'encaixe_confirmado',
    'lembrete_de_sessao',
    'aviso_de_desmarque',
    'aviso_de_cobranca'
  ));
