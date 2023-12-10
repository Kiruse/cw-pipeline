import { render } from 'ink';
import { ComponentType } from 'react';

export interface SubProgramProps<T = unknown> {
  onSubmit(value: T): void;
  onError(error: any): void;
}

export type SubProgramComponent<T = unknown> = ComponentType<SubProgramProps<T>>;

export function renderSubProgram<T = unknown>(SubProgram: SubProgramComponent<T>) {
  return new Promise<T>((resolve, reject) => {
    const inst = render(<SubProgram onSubmit={onSubmit} onError={onError} />);

    function onSubmit(value: T) {
      cleanup();
      resolve(value);
    }

    function onError(error: any) {
      cleanup();
      reject(error);
    }

    function cleanup() {
      inst.cleanup?.();
      inst.unmount();
    }
  });
}
