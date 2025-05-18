// src/components/Row.tsx
import React, { ReactNode } from 'react';
import styles from './Row.module.css';

interface RowProps {
  children: ReactNode;
  style?: React.CSSProperties;
  className?: string;
}

const Row: React.FC<RowProps> = ({ children, style, className }) => {
  return (
    <div className={`${styles.row} ${className || ''}`} style={{ display: 'flex', gap: '20px', flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', ...style }}>
      {children}
    </div>
  );
};

export default Row;