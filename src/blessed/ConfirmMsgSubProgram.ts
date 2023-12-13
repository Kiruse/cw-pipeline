import { Event } from '@kiruse/typed-events';
import blessed, { Widgets } from 'blessed';
import YAML from 'yaml';
import { SubProgram } from '../subprogram';

export default class ConfirmMsgSubProgram extends SubProgram<boolean> {
  constructor(private msg: any) {
    super();
  }

  init(screen: Widgets.Screen, onTerminate: Event<void, boolean>, onError: Event<any>): void {
    screen.key(['escape'], () => onTerminate.emit(undefined, false));
    screen.key(['return'], () => onTerminate.emit(undefined, true));

    screen.append(
      blessed.textbox({
        content: YAML.stringify(this.msg, { indent: 2 }),
        height: '100%-1',
        left: 2,
      })
    );

    screen.append(
      blessed.text({
        content: 'Is this message correct? Press ESC to cancel, RETURN to confirm.',
      })
    );
  }
}
