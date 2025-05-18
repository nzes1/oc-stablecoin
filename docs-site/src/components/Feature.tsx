import React from 'react';
import styles from './Feature.module.css';

interface FeatureProps {
  title: string;
  description: string;
  icon?: string;
}

const Feature: React.FC<FeatureProps> = ({ title, description, icon }) => {
  return (
    <div className={styles.feature}>
      {icon && <div className={styles.featureIcon}>{icon}</div>}
      <h3>{title}</h3>
      <p>{description}</p>
    </div>
  );
};

export default Feature;