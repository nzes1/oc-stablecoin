import React from 'react';
import styles from './Hero.module.css'; // Create Hero.module.css

interface HeroProps {
  background?: string;
  textColor?: string;
  title: string;
  subtitle?: string;
  buttons?: {
    text: string;
    href: string;
    className?: string;
  }[];
}

const Hero: React.FC<HeroProps> = ({
  background,
  textColor,
  title,
  subtitle,
  buttons,
}) => {
  const heroStyle = {
    background: background || 'var(--ifm-color-primary)', // Use theme primary color as default
    color: textColor || 'var(--ifm-font-color-base)', // Use theme base font color as default
    padding: '4rem 0',
    textAlign: 'center',
  };

  return (
    <div className={styles.hero} style={heroStyle}>
      <div className="container">
        <h1 className={styles.heroTitle}>{title}</h1>
        {subtitle && <p className={styles.heroSubtitle}>{subtitle}</p>}
        {buttons && (
          <div className={styles.heroButtons}>
            {buttons.map((button, index) => (
              <a
                key={index}
                className={`button ${button.className || 'button--primary button--lg'}`}
                href={button.href}
              >
                <span dangerouslySetInnerHTML={{ __html: button.text }} />
              </a>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default Hero;