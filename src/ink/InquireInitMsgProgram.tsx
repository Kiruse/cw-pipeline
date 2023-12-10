import { useState } from 'react';
import { SubProgramProps } from '../ink-utils';
import { Text } from 'ink';

export default function InquireInitMsgProgram({ onSubmit, onError }: SubProgramProps) {
  // TODO
  const [msg, setMsg] = useState('');
  return <Text color="red">Not yet implemented, sorry!</Text>
}
