import blessed from 'blessed';
import { Event } from '@kiruse/typed-events';

export abstract class SubProgram<T = void> {
  abstract init(screen: blessed.Widgets.Screen, onTerminate: Event<void, T>, onError: Event<any>): void;
  get title() { return 'cw-pipeline' }
}

export function runSubProgram<T = void>(prog: SubProgram<T>) {
  return new Promise<T>((resolve, reject) => {
    const screen = blessed.screen({
      smartCSR: true,
      title: prog.title,
    });

    const onTerminate = Event<void, T>();
    const onError = Event<any>();

    onTerminate.once(({ result }) => {
      resolve(result!);
      screen.destroy();
    });

    onError.once(err => {
      reject(err);
      screen.destroy();
    });

    prog.init(screen, onTerminate, onError);
    screen.render();
  });
}
