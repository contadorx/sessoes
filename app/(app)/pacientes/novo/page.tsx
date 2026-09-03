import Link from "next/link";
import { FormPaciente } from "@/components/app/FormPaciente";
import { criarPaciente } from "../acoes";
import { envioAutomaticoLigado } from "@/lib/promessa";

export const metadata = { title: "Novo paciente" };

export default function NovoPaciente() {
  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/pacientes" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← pacientes
      </Link>

      <h1 className="mt-2 font-serif text-[28px] leading-tight tracking-[-0.015em]">
        Cadastrar paciente
      </h1>
      <p className="mt-2 max-w-[62ch] text-[13.5px] leading-relaxed text-tinta2">
        O combinado é opcional agora — dá para cadastrar quem ainda está na
        triagem e definir dia, hora e valor depois.
      </p>

      <div className="mt-6">
        <FormPaciente
          acao={criarPaciente}
          comEnquadre
          rotuloBotao="Cadastrar"
          envioAutomatico={envioAutomaticoLigado()}
        />
      </div>
    </div>
  );
}
