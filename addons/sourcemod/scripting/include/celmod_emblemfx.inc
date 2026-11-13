// |CelMod| emblem effects: what every emblem's shots and held aura look like.
//
// Included at the end of celmod-collectibles.sp. Each emblem has its own shot style ("fx" in collectibles.txt) and
// its own aura while it is held ("aura"). The styles are built from layers: textured beams (lightning, crystal,
// physics, laser), coloured dots, glows, rings, sparks and short dynamic lights, so emblems of the same family look
// different from each other and not just recoloured.
//
// The game sends at most 32 temporary effects to a player each update, so every style stays well under that.

#if defined _celmod_emblemfx_included
 #endinput
#endif
#define _celmod_emblemfx_included

// Textures, each with a stock fallback in case a server is missing one.
int g_iFxGlow, g_iFxSoftGlow, g_iFxFlame, g_iFxEmber, g_iFxSteam, g_iFxBlueGlow, g_iFxPurpleGlow, g_iFxRedGlow, g_iFxYellowGlow, g_iFxGreenGlow, g_iFxOrangeGlow, g_iFxBlackBall, g_iFxExplosion;
int g_iBmLaser, g_iBmLightning, g_iBmPhys, g_iBmCrystal, g_iBmXBeam, g_iBmBlue, g_iBmShock, g_iBmSpine, g_iBmHalo;

char g_sFxZap[PLATFORM_MAX_PATH], g_sFxBoom[PLATFORM_MAX_PATH], g_sFxSplash[PLATFORM_MAX_PATH], g_sFxGlass[PLATFORM_MAX_PATH], g_sFxPulse[PLATFORM_MAX_PATH], g_sFxThunder[PLATFORM_MAX_PATH];

float g_fNextAura[MAXPLAYERS + 1];
float g_fAuraLast[MAXPLAYERS + 1][3];
float g_fAuraSpin[MAXPLAYERS + 1];

ConVar g_cvAura;

int Fx_PrecacheTexture(const char[] sPath, const char[] sFallback)
{
	char sFile[PLATFORM_MAX_PATH];

	Format(sFile, sizeof(sFile), "materials/%s", sPath);

	return PrecacheModel(FileExists(sFile, true) ? sPath : sFallback, true);
}

void Fx_PrecacheSound(char[] sOut, int iMaxLength, const char[] sPath, const char[] sFallback)
{
	char sFile[PLATFORM_MAX_PATH];

	Format(sFile, sizeof(sFile), "sound/%s", sPath);

	strcopy(sOut, iMaxLength, FileExists(sFile, true) ? sPath : sFallback);

	PrecacheSound(sOut, true);
}

void Fx_Precache()
{
	g_iFxGlow = Fx_PrecacheTexture("sprites/glow04_noz.vmt", "sprites/glow04_noz.vmt");
	g_iFxSoftGlow = Fx_PrecacheTexture("sprites/light_glow03.vmt", "sprites/glow04_noz.vmt");
	g_iFxFlame = Fx_PrecacheTexture("sprites/flamelet1.vmt", "sprites/glow04_noz.vmt");
	g_iFxEmber = Fx_PrecacheTexture("sprites/plasmaember.vmt", "sprites/glow04_noz.vmt");
	g_iFxSteam = Fx_PrecacheTexture("sprites/steam1.vmt", "sprites/glow04_noz.vmt");
	g_iFxBlueGlow = Fx_PrecacheTexture("sprites/blueglow2.vmt", "sprites/glow04_noz.vmt");
	g_iFxPurpleGlow = Fx_PrecacheTexture("sprites/purpleglow1.vmt", "sprites/glow04_noz.vmt");
	g_iFxRedGlow = Fx_PrecacheTexture("sprites/redglow1.vmt", "sprites/glow04_noz.vmt");
	g_iFxYellowGlow = Fx_PrecacheTexture("sprites/yellowglow1.vmt", "sprites/light_glow03.vmt");
	g_iFxGreenGlow = Fx_PrecacheTexture("sprites/greenglow1.vmt", "sprites/glow04_noz.vmt");
	g_iFxOrangeGlow = Fx_PrecacheTexture("sprites/orangeglow1.vmt", "sprites/flamelet1.vmt");
	g_iFxBlackBall = Fx_PrecacheTexture("sprites/strider_blackball.vmt", "sprites/purpleglow1.vmt");
	g_iFxExplosion = Fx_PrecacheTexture("sprites/zerogxplode.vmt", "sprites/flamelet1.vmt");

	g_iBmLaser = Fx_PrecacheTexture("sprites/laserbeam.vmt", "sprites/laserbeam.vmt");
	g_iBmLightning = Fx_PrecacheTexture("sprites/lgtning.vmt", "sprites/laserbeam.vmt");
	g_iBmPhys = Fx_PrecacheTexture("sprites/physbeam.vmt", "sprites/laserbeam.vmt");
	g_iBmCrystal = Fx_PrecacheTexture("sprites/crystal_beam1.vmt", "sprites/laserbeam.vmt");
	g_iBmXBeam = Fx_PrecacheTexture("sprites/xbeam2.vmt", "sprites/laserbeam.vmt");
	g_iBmBlue = Fx_PrecacheTexture("sprites/bluelaser1.vmt", "sprites/laserbeam.vmt");
	g_iBmShock = Fx_PrecacheTexture("sprites/rollermine_shock.vmt", "sprites/lgtning.vmt");
	g_iBmSpine = Fx_PrecacheTexture("sprites/hydraspinalcord.vmt", "sprites/physbeam.vmt");
	g_iBmHalo = Fx_PrecacheTexture("sprites/halo01.vmt", "sprites/glow04_noz.vmt");

	Fx_PrecacheSound(g_sFxZap, sizeof(g_sFxZap), "ambient/energy/zap7.wav", "ambient/energy/zap1.wav");
	Fx_PrecacheSound(g_sFxBoom, sizeof(g_sFxBoom), "ambient/explosions/explode_4.wav", "ambient/explosions/exp2.wav");
	Fx_PrecacheSound(g_sFxSplash, sizeof(g_sFxSplash), "ambient/water/water_splash2.wav", "ambient/water/water_splash1.wav");
	Fx_PrecacheSound(g_sFxGlass, sizeof(g_sFxGlass), "physics/glass/glass_sheet_break1.wav", "physics/glass/glass_impact_bullet4.wav");
	Fx_PrecacheSound(g_sFxPulse, sizeof(g_sFxPulse), "weapons/airboat/airboat_gun_energy1.wav", "ambient/energy/zap1.wav");
	Fx_PrecacheSound(g_sFxThunder, sizeof(g_sFxThunder), "ambient/levels/labs/electric_explosion4.wav", "ambient/levels/labs/electric_explosion1.wav");
}

//Building blocks:
void Fx_Color(int iOut[4], int iR, int iG, int iB, int iA = 255)
{
	iOut[0] = iR;
	iOut[1] = iG;
	iOut[2] = iB;
	iOut[3] = iA;
}

// A colour part of the way towards white (fAmount 0 to 1), for bright cores.
void Fx_Lighter(const int iColor[4], float fAmount, int iOut[4])
{
	for (int i = 0; i < 3; i++)
	{
		iOut[i] = iColor[i] + RoundToFloor((255 - iColor[i]) * fAmount);
	}

	iOut[3] = iColor[3];
}

void Fx_Darker(const int iColor[4], float fAmount, int iOut[4])
{
	for (int i = 0; i < 3; i++)
	{
		iOut[i] = RoundToFloor(iColor[i] * (1.0 - fAmount));
	}

	iOut[3] = iColor[3];
}

void Fx_Hue(float fHue, int iOut[4])
{
	int iRGB[3];

	HSVtoRGB(fHue, 1.0, 1.0, iRGB);

	iOut[0] = iRGB[0];
	iOut[1] = iRGB[1];
	iOut[2] = iRGB[2];
	iOut[3] = 255;
}

void Fx_Beam(const float fA[3], const float fB[3], int iModel, float fWidth, float fEndWidth, float fLife, float fAmplitude, const int iColor[4], int iSpeed = 0, int iFrameRate = 15)
{
	TE_SetupBeamPoints(fA, fB, iModel, g_iBmHalo, 0, iFrameRate, fLife, fWidth, fEndWidth, 1, fAmplitude, iColor, iSpeed);
	TE_SendToAll();
}

void Fx_Ring(const float fCenter[3], float fFrom, float fTo, int iModel, float fWidth, float fLife, float fAmplitude, const int iColor[4])
{
	TE_SetupBeamRingPoint(fCenter, fFrom, fTo, iModel, g_iBmHalo, 0, 15, fLife, fWidth, fAmplitude, iColor, 10, 0);
	TE_SendToAll();
}

void Fx_Glow(const float fPos[3], int iModel, float fScale, float fLife, int iBrightness = 220)
{
	TE_SetupGlowSprite(fPos, iModel, fLife, fScale, iBrightness);
	TE_SendToAll();
}

// A coloured blob of light: a very short, fat beam.
void Fx_Dot(const float fPos[3], const int iColor[4], float fSize, float fLife)
{
	float fA[3], fB[3];

	fA = fPos;
	fB = fPos;

	fA[2] -= fSize * 0.3;
	fB[2] += fSize * 0.3;

	TE_SetupBeamPoints(fA, fB, g_iBmLaser, g_iBmHalo, 0, 15, fLife, fSize, fSize, 1, 0.0, iColor, 0);
	TE_SendToAll();
}

// Lights up the area around a point for a moment.
void Fx_Light(const float fPos[3], const int iColor[4], float fRadius, float fTime, int iExponent = 5)
{
	TE_Start("Dynamic Light");
	TE_WriteVector("m_vecOrigin", fPos);
	TE_WriteNum("r", iColor[0]);
	TE_WriteNum("g", iColor[1]);
	TE_WriteNum("b", iColor[2]);
	TE_WriteNum("exponent", iExponent);
	TE_WriteFloat("m_fRadius", fRadius);
	TE_WriteFloat("m_fTime", fTime);
	TE_WriteFloat("m_fDecay", fRadius / fTime);
	TE_SendToAll();
}

void Fx_Sparks(const float fPos[3], const float fDirection[3], int iMagnitude, int iTrail)
{
	TE_SetupSparks(fPos, fDirection, iMagnitude, iTrail);
	TE_SendToAll();
}

// A point part of the way from A to B.
void Fx_Lerp(const float fA[3], const float fB[3], float fT, float fOut[3])
{
	for (int i = 0; i < 3; i++)
	{
		fOut[i] = fA[i] + (fB[i] - fA[i]) * fT;
	}
}

// Two directions at right angles to a line, for spirals and side by side beams.
void Fx_Axes(const float fA[3], const float fB[3], float fForward[3], float fSide[3], float fUp[3])
{
	float fAngles[3];

	MakeVectorFromPoints(fA, fB, fForward);
	NormalizeVector(fForward, fForward);

	GetVectorAngles(fForward, fAngles);
	GetAngleVectors(fAngles, NULL_VECTOR, fSide, fUp);
}

// A spiral wound around the line from A to B, drawn as short beams.
void Fx_Helix(const float fA[3], const float fB[3], float fRadius, float fTurns, int iSegments, float fPhase, int iModel, float fWidth, float fLife, const int iColor[4])
{
	float fForward[3], fSide[3], fUp[3], fLast[3], fPoint[3], fOnLine[3];

	Fx_Axes(fA, fB, fForward, fSide, fUp);

	for (int i = 0; i <= iSegments; i++)
	{
		float fT = float(i) / float(iSegments);
		float fTurn = fPhase + fT * fTurns * 6.2832;

		// The spiral starts tight at the hand and opens up.
		float fR = fRadius * (0.3 + 0.7 * fT);

		Fx_Lerp(fA, fB, fT, fOnLine);

		for (int k = 0; k < 3; k++)
		{
			fPoint[k] = fOnLine[k] + fSide[k] * Cosine(fTurn) * fR + fUp[k] * Sine(fTurn) * fR;
		}

		if (i > 0)
		{
			Fx_Beam(fLast, fPoint, iModel, fWidth, fWidth, fLife, 0.0, iColor);
		}

		fLast = fPoint;
	}
}

// A jagged bolt from A to B.
void Fx_Bolt(const float fA[3], const float fB[3], int iSegments, float fJitter, int iModel, float fWidth, float fLife, const int iColor[4])
{
	float fLast[3], fPoint[3];

	fLast = fA;

	for (int i = 1; i <= iSegments; i++)
	{
		Fx_Lerp(fA, fB, float(i) / float(iSegments), fPoint);

		if (i < iSegments)
		{
			fPoint[0] += GetRandomFloat(-fJitter, fJitter);
			fPoint[1] += GetRandomFloat(-fJitter, fJitter);
			fPoint[2] += GetRandomFloat(-fJitter, fJitter);
		}

		Fx_Beam(fLast, fPoint, iModel, fWidth, fWidth * 0.7, fLife, 0.0, iColor);

		fLast = fPoint;
	}
}

// Beams bursting out of a point in every direction.
void Fx_Starburst(const float fCenter[3], int iCount, float fLength, int iModel, float fWidth, float fLife, const int iColor[4], bool bFlat = false)
{
	float fAngles[3], fDirection[3], fEnd[3];

	for (int i = 0; i < iCount; i++)
	{
		fAngles[0] = bFlat ? GetRandomFloat(-10.0, 10.0) : GetRandomFloat(-80.0, 80.0);
		fAngles[1] = 360.0 * i / iCount + GetRandomFloat(-10.0, 10.0);

		GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

		float fReach = fLength * GetRandomFloat(0.6, 1.0);

		for (int k = 0; k < 3; k++)
		{
			fEnd[k] = fCenter[k] + fDirection[k] * fReach;
		}

		Fx_Beam(fCenter, fEnd, iModel, fWidth, 0.5, fLife, 0.0, iColor);
	}
}

// A sprite that flies to the target with a coloured trail behind it.
void Fx_Missile(int iItem, const float fStart[3], const float fEnd[3], const int iColor[4], float fSpeed, float fScale, bool bGravity, float fTrailWidth, float fTrailLife)
{
	float fA[3], fB[3];
	int iColor2[4];

	fA = fStart;
	fB = fEnd;

	iColor2 = iColor;

	int iSprite = LaunchSprite(iItem, fA, fB, iColor2, fSpeed, fScale, bGravity);

	if (iSprite != -1 && fTrailWidth > 0.0)
	{
		TE_SetupBeamFollow(iSprite, g_iBmLaser, g_iBmHalo, fTrailLife, fTrailWidth, 0.5, 1, iColor2);
		TE_SendToAll();
	}
}

//Shot styles, one per emblem:
// True when the style was one of these (the older, simpler styles are still drawn by DrawShotEffect).
bool DrawStyledShot(int iClient, int iItem, const char[] sFx, float fStart[3], float fEnd[3], float fDirection[3], const int iColor[4])
{
	float fUp[3] = { 0.0, 0.0, 1.0 }, fPoint[3], fHigh[3], fForward[3], fSide[3], fAxisUp[3];
	int iCore[4], iDeep[4], iTint[4];

	Fx_Lighter(iColor, 0.6, iCore);
	Fx_Darker(iColor, 0.5, iDeep);

	float fNormal[3];

	fNormal[0] = -fDirection[0];
	fNormal[1] = -fDirection[1];
	fNormal[2] = -fDirection[2];

	if (StrEqual(sFx, "snowstorm"))
	{
		// Blizzard: a gust of snow, a pale crystal streak, and a double ring of frost where it lands.
		Fx_Missile(iItem, fStart, fEnd, iCore, 1200.0, 0.35, false, 6.0, 0.4);

		for (int i = 0; i < 4; i++)
		{
			Fx_Lerp(fStart, fEnd, GetRandomFloat(0.2, 0.95), fPoint);

			fPoint[0] += GetRandomFloat(-24.0, 24.0);
			fPoint[1] += GetRandomFloat(-24.0, 24.0);
			fPoint[2] += GetRandomFloat(-16.0, 16.0);

			Fx_Glow(fPoint, g_iFxGlow, GetRandomFloat(0.15, 0.3), GetRandomFloat(0.4, 0.9), 200);
		}

		Fx_Beam(fStart, fEnd, g_iBmCrystal, 3.0, 1.0, 0.25, 2.0, iColor);
		Fx_Ring(fEnd, 4.0, 70.0, g_iBmCrystal, 6.0, 0.5, 0.0, iCore);
		Fx_Ring(fEnd, 70.0, 10.0, g_iBmLaser, 3.0, 0.6, 0.0, iColor);
		Fx_Light(fEnd, iColor, 140.0, 0.4);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "frostline"))
	{
		// Frost: a thin line of ice crystals that glitter along the whole path.
		Fx_Beam(fStart, fEnd, g_iBmCrystal, 2.0, 2.0, 0.35, 0.0, iCore);
		Fx_Beam(fStart, fEnd, g_iBmLaser, 6.0, 1.0, 0.2, 0.0, iColor);

		for (int i = 1; i <= 5; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 5.5, fPoint);
			Fx_Glow(fPoint, g_iFxBlueGlow, 0.12, 0.6, 230);
		}

		Fx_Ring(fEnd, 2.0, 36.0, g_iBmCrystal, 3.0, 0.4, 0.0, iCore);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "shards"))
	{
		// Glacier: three ice shards that meet at the target, then spikes burst up out of it.
		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		for (int i = 0; i < 3; i++)
		{
			float fTurn = 6.2832 * i / 3.0;

			for (int k = 0; k < 3; k++)
			{
				fPoint[k] = fStart[k] + fSide[k] * Cosine(fTurn) * 10.0 + fAxisUp[k] * Sine(fTurn) * 10.0;
			}

			Fx_Beam(fPoint, fEnd, g_iBmCrystal, 7.0, 0.5, 0.35, 0.0, i == 0 ? iCore : iColor);
		}

		for (int i = 0; i < 4; i++)
		{
			fHigh = fEnd;
			fHigh[0] += GetRandomFloat(-30.0, 30.0);
			fHigh[1] += GetRandomFloat(-30.0, 30.0);
			fHigh[2] += GetRandomFloat(30.0, 70.0);

			Fx_Beam(fEnd, fHigh, g_iBmCrystal, 8.0, 0.5, 0.7, 0.0, iCore);
		}

		Fx_Ring(fEnd, 8.0, 110.0, g_iBmLaser, 10.0, 0.6, 0.0, iColor);
		Fx_Light(fEnd, iColor, 200.0, 0.6);

		PlayShotSound(iClient, g_sFxGlass);
	} else if (StrEqual(sFx, "waterbolt"))
	{
		// Water: an arcing bolt of water that splashes and sends ripples out.
		Fx_Missile(iItem, fStart, fEnd, iColor, 900.0, 0.45, true, 5.0, 0.35);

		SpriteSpray(fEnd, fUp, g_Items[iItem].iSpriteIndex, 160, 0.9, 5);

		fPoint = fEnd;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 6.0, 60.0, g_iBmPhys, 4.0, 0.6, 0.0, iCore);
		Fx_Ring(fPoint, 2.0, 30.0, g_iBmPhys, 3.0, 0.8, 0.0, iColor);

		PlayShotSound(iClient, SOUND_WATER);
	} else if (StrEqual(sFx, "wave"))
	{
		// Tsunami: a broad rolling wave that crashes into its target.
		Fx_Beam(fStart, fEnd, g_iBmPhys, 18.0, 46.0, 0.35, 6.0, iColor, 0, 30);
		Fx_Beam(fStart, fEnd, g_iBmPhys, 6.0, 16.0, 0.3, 3.0, iCore, 0, 30);

		SpriteSpray(fEnd, fUp, g_Items[iItem].iSpriteIndex, 260, 1.0, 8);

		for (int i = 0; i < 3; i++)
		{
			fPoint = fEnd;
			fPoint[2] += 2.0 + i * 6.0;

			Fx_Ring(fPoint, 10.0 + i * 20.0, 120.0 + i * 40.0, g_iBmPhys, 6.0, 0.5 + i * 0.2, 0.0, i == 1 ? iCore : iColor);
		}

		PlayShotSound(iClient, g_sFxSplash);
	} else if (StrEqual(sFx, "acidglob"))
	{
		// Acid: a lobbed glob that hisses and bubbles where it lands.
		Fx_Missile(iItem, fStart, fEnd, iColor, 800.0, 0.5, true, 4.0, 0.5);

		for (int i = 0; i < 4; i++)
		{
			fPoint = fEnd;
			fPoint[0] += GetRandomFloat(-20.0, 20.0);
			fPoint[1] += GetRandomFloat(-20.0, 20.0);
			fPoint[2] += 4.0 + i * 8.0;

			Fx_Dot(fPoint, i % 2 ? iCore : iColor, GetRandomFloat(4.0, 9.0), GetRandomFloat(0.4, 1.0));
		}

		Fx_Ring(fEnd, 4.0, 48.0, g_iBmLaser, 5.0, 0.7, 2.0, iColor);
		Fx_Light(fEnd, iColor, 120.0, 0.7);

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "venomspiral"))
	{
		// Venom: a dark green serpent coiling around a pale fang of light.
		Fx_Beam(fStart, fEnd, g_iBmLaser, 2.0, 2.0, 0.2, 0.0, iCore);
		Fx_Helix(fStart, fEnd, 9.0, 2.5, 8, GetGameTime() * 4.0, g_iBmSpine, 3.0, 0.35, iDeep);
		Fx_Glow(fEnd, g_iFxGreenGlow, 0.5, 0.4);
		Fx_Ring(fEnd, 30.0, 4.0, g_iBmLaser, 4.0, 0.4, 0.0, iColor);

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "arc"))
	{
		// Energy: a glowing ember with arcs of lightning crackling along its path.
		Fx_Missile(iItem, fStart, fEnd, iColor, 1600.0, 0.5, false, 3.0, 0.2);
		Fx_Beam(fStart, fEnd, g_iBmLightning, 5.0, 5.0, 0.2, 4.0, iColor, 0, 30);
		Fx_Beam(fStart, fEnd, g_iBmLightning, 2.0, 2.0, 0.15, 7.0, iCore, 0, 30);

		Fx_Sparks(fEnd, fNormal, 3, 2);

		TE_SetupEnergySplash(fEnd, fNormal, false);
		TE_SendToAll();

		Fx_Light(fEnd, iColor, 150.0, 0.25);

		PlayShotSound(iClient, g_sFxZap);
	} else if (StrEqual(sFx, "pulse"))
	{
		// Pulse: dashes of light that get brighter as they reach the target, then shock rings.
		for (int i = 0; i < 4; i++)
		{
			float fT = i / 4.0;

			Fx_Lerp(fStart, fEnd, fT + 0.04, fPoint);
			Fx_Lerp(fStart, fEnd, fT + 0.18, fHigh);

			Fx_Beam(fPoint, fHigh, g_iBmBlue, 3.0 + i * 2.0, 3.0 + i * 2.0, 0.2, 0.0, i == 3 ? iCore : iColor);
		}

		Fx_Ring(fEnd, 2.0, 40.0, g_iBmLaser, 6.0, 0.25, 0.0, iCore);
		Fx_Ring(fEnd, 20.0, 80.0, g_iBmBlue, 3.0, 0.4, 0.0, iColor);

		TE_SetupEnergySplash(fEnd, fNormal, true);
		TE_SendToAll();

		PlayShotSound(iClient, g_sFxPulse);
	} else if (StrEqual(sFx, "laser"))
	{
		// Laser: a razor-thin bright core in a soft glow, burning a hot dot where it hits.
		Fx_Beam(fStart, fEnd, g_iBmLaser, 1.5, 1.5, 0.12, 0.0, iCore, 0, 30);
		Fx_Beam(fStart, fEnd, g_iBmLaser, 7.0, 7.0, 0.12, 0.0, iDeep, 0, 30);

		Fx_Glow(fEnd, g_iFxRedGlow, 0.25, 0.15, 255);
		Fx_Sparks(fEnd, fNormal, 1, 1);

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "static"))
	{
		// Static: a jagged, flickering bolt with sparks spitting off it.
		Fx_Bolt(fStart, fEnd, 6, 14.0, g_iBmLightning, 3.0, 0.15, iCore);
		Fx_Beam(fStart, fEnd, g_iBmShock, 8.0, 8.0, 0.15, 3.0, iColor, 0, 30);

		Fx_Lerp(fStart, fEnd, GetRandomFloat(0.3, 0.7), fPoint);

		Fx_Sparks(fPoint, fUp, 2, 2);
		Fx_Sparks(fEnd, fNormal, 3, 3);

		PlayShotSound(iClient, g_sFxZap);
	} else if (StrEqual(sFx, "gemtwin"))
	{
		// Ruby: two red strands twisting round each other, glinting where they meet the target.
		float fPhase = GetGameTime() * 6.0;

		Fx_Beam(fStart, fEnd, g_iBmLaser, 1.5, 1.5, 0.2, 0.0, iCore);
		Fx_Helix(fStart, fEnd, 6.0, 2.0, 5, fPhase, g_iBmLaser, 2.5, 0.25, iColor);
		Fx_Helix(fStart, fEnd, 6.0, 2.0, 5, fPhase + 3.1416, g_iBmLaser, 2.5, 0.25, iDeep);

		Fx_Glow(fEnd, g_iFxRedGlow, 0.35, 0.3, 255);
		Fx_Glow(fEnd, g_iFxGlow, 0.15, 0.5, 255);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "gemprism"))
	{
		// Emerald: a square-cut prism of four green beams around a white core.
		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		for (int i = 0; i < 4; i++)
		{
			float fTurn = 1.5708 * i + 0.7854;
			float fOffset[3];

			for (int k = 0; k < 3; k++)
			{
				fOffset[k] = fSide[k] * Cosine(fTurn) * 4.0 + fAxisUp[k] * Sine(fTurn) * 4.0;
				fPoint[k] = fStart[k] + fOffset[k];
				fHigh[k] = fEnd[k] + fOffset[k];
			}

			Fx_Beam(fPoint, fHigh, g_iBmCrystal, 2.0, 2.0, 0.2, 0.0, iColor);
		}

		Fx_Beam(fStart, fEnd, g_iBmLaser, 1.5, 1.5, 0.2, 0.0, iCore);
		Fx_Ring(fEnd, 2.0, 30.0, g_iBmCrystal, 4.0, 0.3, 0.0, iCore);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "gemstar"))
	{
		// Sapphire: a deep blue beam that ends in a six pointed star of light.
		Fx_Beam(fStart, fEnd, g_iBmBlue, 4.0, 2.0, 0.2, 0.0, iColor);
		Fx_Beam(fStart, fEnd, g_iBmLaser, 1.0, 1.0, 0.2, 0.0, iCore);

		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		for (int i = 0; i < 6; i++)
		{
			float fTurn = 6.2832 * i / 6.0 + GetGameTime();

			for (int k = 0; k < 3; k++)
			{
				fPoint[k] = fEnd[k] - fForward[k] * 4.0 + fSide[k] * Cosine(fTurn) * 22.0 + fAxisUp[k] * Sine(fTurn) * 22.0;
			}

			Fx_Beam(fEnd, fPoint, g_iBmLaser, 3.0, 0.5, 0.3, 0.0, iCore);
		}

		Fx_Glow(fEnd, g_iFxBlueGlow, 0.4, 0.3, 255);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "gemorbit"))
	{
		// Amethyst: a violet beam with crystals spiralling down its length.
		Fx_Beam(fStart, fEnd, g_iBmLaser, 3.0, 3.0, 0.2, 0.0, iColor);

		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		for (int i = 1; i <= 6; i++)
		{
			float fT = i / 6.5;
			float fTurn = fT * 12.0 + GetGameTime() * 5.0;

			Fx_Lerp(fStart, fEnd, fT, fHigh);

			for (int k = 0; k < 3; k++)
			{
				fPoint[k] = fHigh[k] + fSide[k] * Cosine(fTurn) * 9.0 + fAxisUp[k] * Sine(fTurn) * 9.0;
			}

			Fx_Dot(fPoint, i % 2 ? iCore : iColor, 5.0, 0.35);
		}

		Fx_Light(fEnd, iColor, 110.0, 0.3);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "plasmaflow"))
	{
		// Plasma: a thick, writhing stream with a white-hot core and a blob of plasma riding it.
		Fx_Beam(fStart, fEnd, g_iBmPhys, 12.0, 14.0, 0.2, 5.0, iColor, 0, 40);
		Fx_Beam(fStart, fEnd, g_iBmLaser, 3.0, 3.0, 0.2, 0.0, iCore);

		Fx_Missile(iItem, fStart, fEnd, iCore, 1800.0, 0.6, false, 0.0, 0.0);

		Fx_Glow(fEnd, g_iFxPurpleGlow, 0.6, 0.3);
		Fx_Light(fEnd, iColor, 160.0, 0.3);

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "ion"))
	{
		// Ion: a dead straight cyan beam with rungs of charge crackling across it.
		Fx_Beam(fStart, fEnd, g_iBmBlue, 4.0, 4.0, 0.25, 0.0, iColor);

		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		for (int i = 1; i <= 4; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 5.0, fHigh);

			float fTurn = GetRandomFloat(0.0, 6.2832);
			float fA[3], fB[3];

			for (int k = 0; k < 3; k++)
			{
				fA[k] = fHigh[k] + fSide[k] * Cosine(fTurn) * 10.0 + fAxisUp[k] * Sine(fTurn) * 10.0;
				fB[k] = fHigh[k] - fSide[k] * Cosine(fTurn) * 10.0 - fAxisUp[k] * Sine(fTurn) * 10.0;
			}

			Fx_Beam(fA, fB, g_iBmLightning, 2.0, 2.0, 0.2, 3.0, iCore, 0, 30);
		}

		Fx_Light(fEnd, iColor, 140.0, 0.3);

		PlayShotSound(iClient, g_sFxZap);
	} else if (StrEqual(sFx, "prism"))
	{
		// Prism: white light that fans out into a rainbow and meets again at the target.
		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		for (int i = 0; i < 6; i++)
		{
			Fx_Hue(i * 60.0, iTint);

			float fSpread = (i - 2.5) * 6.0;

			for (int k = 0; k < 3; k++)
			{
				fPoint[k] = fStart[k] + fSide[k] * fSpread;
			}

			Fx_Lerp(fStart, fEnd, 0.5, fHigh);

			for (int k = 0; k < 3; k++)
			{
				fHigh[k] += fSide[k] * fSpread * 3.0;
			}

			Fx_Beam(fPoint, fHigh, g_iBmLaser, 2.5, 2.5, 0.25, 0.0, iTint);
			Fx_Beam(fHigh, fEnd, g_iBmLaser, 2.5, 1.0, 0.25, 0.0, iTint);
		}

		Fx_Glow(fEnd, g_iFxGlow, 0.4, 0.3, 255);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "lava"))
	{
		// Magma: a lobbed blob of molten rock that splatters fire and lights the ground up orange.
		Fx_Missile(iItem, fStart, fEnd, iColor, 850.0, 0.7, true, 6.0, 0.6);

		SpriteSpray(fEnd, fUp, g_iFxFlame, 220, 0.7, 6);

		Fx_Ring(fEnd, 4.0, 64.0, g_iBmLaser, 8.0, 0.5, 3.0, iColor);

		TE_SetupDust(fEnd, fUp, 20.0, 1.0);
		TE_SendToAll();

		Fx_Light(fEnd, iColor, 220.0, 0.8, 6);

		PlayShotSound(iClient, SOUND_FIREBALL);
	} else if (StrEqual(sFx, "embers"))
	{
		// Ember: a scatter of small burning embers.
		for (int i = 0; i < 3; i++)
		{
			float fTo[3];

			fTo = fEnd;
			fTo[0] += GetRandomFloat(-20.0, 20.0);
			fTo[1] += GetRandomFloat(-20.0, 20.0);
			fTo[2] += GetRandomFloat(-10.0, 10.0);

			Fx_Missile(iItem, fStart, fTo, iColor, GetRandomFloat(1000.0, 1300.0), 0.25, false, i == 0 ? 2.0 : 0.0, 0.3);
		}

		Fx_Sparks(fEnd, fUp, 2, 3);

		PlayShotSound(iClient, SOUND_FIRE);
	} else if (StrEqual(sFx, "comet"))
	{
		// Comet: a fireball with a long burning tail, ending in a fiery blast.
		Fx_Missile(iItem, fStart, fEnd, iColor, 1300.0, 0.9, false, 14.0, 0.8);

		TE_SetupExplosion(fEnd, g_iFxExplosion, 2.0, 15, 0, 0, 0);
		TE_SendToAll();

		Fx_Ring(fEnd, 10.0, 160.0, g_iBmLaser, 12.0, 0.5, 0.0, iColor);
		Fx_Light(fEnd, iColor, 280.0, 0.7, 6);

		PlayShotSound(iClient, SOUND_FIREBALL);
	} else if (StrEqual(sFx, "glitch"))
	{
		// Errors: an error model with a broken, flickering trail of mismatched lines.
		iTint = iColor;

		LaunchModel(iItem, fStart, fEnd, iTint, 1500.0);

		for (int i = 0; i < 4; i++)
		{
			float fA[3], fB[3];

			Fx_Lerp(fStart, fEnd, GetRandomFloat(0.1, 0.9), fA);

			fB = fA;
			fB[0] += GetRandomFloat(-30.0, 30.0);
			fB[1] += GetRandomFloat(-30.0, 30.0);
			fB[2] += GetRandomFloat(-12.0, 12.0);

			Fx_Beam(fA, fB, g_iBmXBeam, GetRandomFloat(2.0, 6.0), 2.0, GetRandomFloat(0.1, 0.3), 0.0, i % 2 ? iColor : iCore);
		}

		Fx_Sparks(fEnd, fUp, 4, 2);

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "nova"))
	{
		// Nova: a burst of white light, rays in every direction and two shock rings.
		Fx_Beam(fStart, fEnd, g_iBmLaser, 4.0, 8.0, 0.2, 0.0, iCore);
		Fx_Starburst(fEnd, 8, 90.0, g_iBmLaser, 4.0, 0.4, iCore);
		Fx_Ring(fEnd, 10.0, 180.0, g_iBmLaser, 10.0, 0.4, 0.0, iCore);
		Fx_Ring(fEnd, 10.0, 260.0, g_iBmPhys, 6.0, 0.7, 0.0, iColor);
		Fx_Glow(fEnd, g_iFxSoftGlow, 1.5, 0.3, 255);
		Fx_Light(fEnd, iColor, 320.0, 0.5, 7);

		PlayShotSound(iClient, g_sFxBoom);
	} else if (StrEqual(sFx, "supernova"))
	{
		// Supernova: a star going off. A column of light, a corona of long rays and three rolling shockwaves.
		fHigh = fEnd;
		fHigh[2] += 320.0;

		Fx_Beam(fStart, fEnd, g_iBmLaser, 6.0, 12.0, 0.2, 0.0, iCore);
		Fx_Beam(fEnd, fHigh, g_iBmPhys, 40.0, 4.0, 0.6, 0.0, iCore);
		Fx_Starburst(fEnd, 10, 160.0, g_iBmLaser, 6.0, 0.6, iColor);

		for (int i = 0; i < 3; i++)
		{
			fPoint = fEnd;
			fPoint[2] += i * 12.0;

			Fx_Ring(fPoint, 10.0, 220.0 + i * 90.0, i == 1 ? g_iBmLaser : g_iBmPhys, 14.0 - i * 3.0, 0.5 + i * 0.25, 0.0, i == 0 ? iCore : iColor);
		}

		Fx_Glow(fEnd, g_iFxSoftGlow, 3.0, 0.5, 255);
		Fx_Light(fEnd, iColor, 520.0, 0.9, 8);

		PlayShotSound(iClient, g_sFxBoom);
	} else if (StrEqual(sFx, "thunder"))
	{
		// Thunder: a thin guiding spark, then a bolt of lightning out of the sky onto the target.
		fHigh = fEnd;
		fHigh[2] += 700.0;

		Handle hTrace = TR_TraceRayFilterEx(fEnd, fHigh, MASK_SOLID, RayType_EndPoint, Filter_WorldOnly, 0);

		if (TR_DidHit(hTrace))
		{
			TR_GetEndPosition(fHigh, hTrace);
		}

		CloseHandle(hTrace);

		Fx_Beam(fStart, fEnd, g_iBmLightning, 1.5, 1.5, 0.1, 2.0, iCore, 0, 30);
		Fx_Bolt(fHigh, fEnd, 6, 30.0, g_iBmLightning, 10.0, 0.25, iCore);
		Fx_Bolt(fHigh, fEnd, 4, 40.0, g_iBmLightning, 4.0, 0.2, iColor);
		Fx_Ring(fEnd, 6.0, 120.0, g_iBmLightning, 8.0, 0.3, 4.0, iColor);
		Fx_Light(fEnd, iCore, 400.0, 0.25, 8);

		PlayShotSound(iClient, g_sFxThunder);
	} else if (StrEqual(sFx, "chainspark"))
	{
		// Spark: a chain of yellow sparks jumping from point to point.
		float fLast[3];

		fLast = fStart;

		for (int i = 1; i <= 4; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 4.0, fPoint);

			if (i < 4)
			{
				fPoint[0] += GetRandomFloat(-16.0, 16.0);
				fPoint[1] += GetRandomFloat(-16.0, 16.0);
				fPoint[2] += GetRandomFloat(-10.0, 10.0);
			}

			Fx_Beam(fLast, fPoint, g_iBmShock, 6.0, 3.0, 0.2, 2.0, iColor, 0, 30);

			TE_SetupMetalSparks(fPoint, fUp);
			TE_SendToAll();

			fLast = fPoint;
		}

		Fx_Light(fEnd, iColor, 120.0, 0.2);

		PlayShotSound(iClient, g_sFxZap);
	} else if (StrEqual(sFx, "healbeam"))
	{
		// Medic: a soft white mending beam with a red cross of light on whoever it touches.
		int iRed[4] = { 255, 40, 40, 255 };

		Fx_Beam(fStart, fEnd, g_iBmPhys, 10.0, 10.0, 0.25, 0.0, iColor, 0, 10);
		Fx_Beam(fStart, fEnd, g_iBmLaser, 2.0, 2.0, 0.25, 0.0, iRed);

		float fA[3], fB[3];

		fA = fEnd;
		fB = fEnd;
		fA[2] += 14.0;
		fB[2] -= 14.0;

		Fx_Beam(fA, fB, g_iBmLaser, 6.0, 6.0, 0.4, 0.0, iRed);

		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		for (int k = 0; k < 3; k++)
		{
			fA[k] = fEnd[k] + fSide[k] * 14.0;
			fB[k] = fEnd[k] - fSide[k] * 14.0;
		}

		Fx_Beam(fA, fB, g_iBmLaser, 6.0, 6.0, 0.4, 0.0, iRed);

		PlayShotSound(iClient, SOUND_HEAL);
	} else if (StrEqual(sFx, "lovebeam"))
	{
		// Pink: two soft pink ribbons curling round each other, blooming at the end.
		float fPhase = GetGameTime() * 3.0;

		Fx_Helix(fStart, fEnd, 7.0, 1.5, 6, fPhase, g_iBmPhys, 4.0, 0.3, iColor);
		Fx_Helix(fStart, fEnd, 7.0, 1.5, 6, fPhase + 3.1416, g_iBmPhys, 4.0, 0.3, iCore);
		Fx_Glow(fEnd, g_iFxPurpleGlow, 0.5, 0.4);
		Fx_Ring(fEnd, 2.0, 40.0, g_iBmPhys, 4.0, 0.5, 0.0, iCore);

		PlayShotSound(iClient, SOUND_HEAL);
	} else if (StrEqual(sFx, "rainbowspray"))
	{
		// Rainbow: a fountain of colour, every drop a different hue.
		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		float fHue = GetGameTime() * 200.0;

		for (int i = 0; i < 8; i++)
		{
			float fAlong = GetRandomFloat(40.0, 220.0);

			for (int k = 0; k < 3; k++)
			{
				fPoint[k] = fStart[k] + fForward[k] * fAlong + fSide[k] * GetRandomFloat(-1.0, 1.0) * fAlong * 0.25 + fAxisUp[k] * GetRandomFloat(-1.0, 1.0) * fAlong * 0.2;
			}

			Fx_Hue(fHue + i * 45.0, iTint);
			Fx_Dot(fPoint, iTint, GetRandomFloat(4.0, 8.0), GetRandomFloat(0.3, 0.7));
		}

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "aurora"))
	{
		// Aurora: shimmering curtains of green and violet light hanging along the path.
		for (int i = 0; i < 5; i++)
		{
			Fx_Lerp(fStart, fEnd, (i + 0.5) / 5.0, fPoint);

			fHigh = fPoint;
			fPoint[2] -= 20.0;
			fHigh[2] += 40.0 + 20.0 * Sine(GetGameTime() * 3.0 + i);

			Fx_Hue(120.0 + i * 40.0, iTint);
			Fx_Beam(fPoint, fHigh, g_iBmPhys, 10.0, 2.0, 0.5, 3.0, iTint, 0, 20);
		}

		Fx_Beam(fStart, fEnd, g_iBmPhys, 4.0, 4.0, 0.3, 4.0, iColor);

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "mist"))
	{
		// Grey: a cool drifting mist.
		SpriteSpray(fStart, fDirection, g_iFxSteam, 500, 0.3, 5);

		Fx_Beam(fStart, fEnd, g_iBmPhys, 6.0, 30.0, 0.4, 2.0, iDeep, 0, 10);

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "sandstorm"))
	{
		// Sandstorm: a scouring blast of sand that kicks up dust where it lands.
		SpriteSpray(fStart, fDirection, g_iFxSteam, 600, 0.45, 6);

		for (int i = 1; i <= 3; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 3.0, fPoint);

			TE_SetupDust(fPoint, fNormal, 18.0 + i * 6.0, 0.8);
			TE_SendToAll();
		}

		Fx_Helix(fStart, fEnd, 14.0, 3.0, 6, GetGameTime() * 5.0, g_iBmPhys, 6.0, 0.3, iColor);

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "tractor"))
	{
		// Magnitude: a spiralling tractor beam with rings of force closing in on what it holds.
		Fx_Helix(fStart, fEnd, 10.0, 3.0, 8, GetGameTime() * 8.0, g_iBmPhys, 3.0, 0.25, iColor);
		Fx_Beam(fStart, fEnd, g_iBmLaser, 1.5, 1.5, 0.2, 0.0, iCore);
		Fx_Ring(fEnd, 70.0, 6.0, g_iBmPhys, 5.0, 0.4, 0.0, iColor);

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "geyser"))
	{
		// Geyser: a column of water erupting out of the ground where it lands.
		Fx_Beam(fStart, fEnd, g_iBmPhys, 3.0, 3.0, 0.2, 2.0, iCore);

		fHigh = fEnd;
		fHigh[2] += 200.0;

		Fx_Beam(fEnd, fHigh, g_iBmPhys, 30.0, 8.0, 0.6, 4.0, iColor, 0, 40);
		Fx_Beam(fEnd, fHigh, g_iBmPhys, 10.0, 2.0, 0.5, 2.0, iCore, 0, 40);

		SpriteSpray(fHigh, fUp, g_Items[iItem].iSpriteIndex, 220, 1.2, 6);

		Fx_Ring(fEnd, 10.0, 90.0, g_iBmPhys, 6.0, 0.6, 0.0, iColor);

		PlayShotSound(iClient, g_sFxSplash);
	} else if (StrEqual(sFx, "gravwell"))
	{
		// Gravitron: a golden gravity well, rings collapsing onto the target from above and below.
		Fx_Beam(fStart, fEnd, g_iBmPhys, 5.0, 5.0, 0.25, 6.0, iColor, 0, 30);

		for (int i = -1; i <= 1; i++)
		{
			fPoint = fEnd;
			fPoint[2] += i * 30.0;

			Fx_Ring(fPoint, 90.0 - FloatAbs(float(i)) * 30.0, 4.0, g_iBmLaser, 5.0, 0.5, 0.0, i == 0 ? iCore : iColor);
		}

		Fx_Glow(fEnd, g_iFxYellowGlow, 0.6, 0.4);

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "tornado"))
	{
		// Tornado: a twister spinning up out of the target, wider the higher it goes.
		Fx_Beam(fStart, fEnd, g_iBmPhys, 4.0, 4.0, 0.25, 3.0, iColor);

		for (int i = 0; i < 5; i++)
		{
			fPoint = fEnd;
			fPoint[2] += i * 34.0;

			Fx_Ring(fPoint, 8.0 + i * 12.0, 30.0 + i * 26.0, g_iBmPhys, 6.0, 0.6, 2.0, i % 2 ? iCore : iColor);
		}

		TE_SetupDust(fEnd, fUp, 40.0, 1.2);
		TE_SendToAll();

		PlayShotSound(iClient, SOUND_STEAM);
	} else {
		return false;
	}

	return true;
}

//Auras: a look for every emblem while it is held out, seen by everyone.
public void Fx_ThinkAuras()
{
	if (!g_cvAura.BoolValue)
	{
		return;
	}

	float fNow = GetGameTime();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !g_bHoldingGravGun[i] || g_iActiveEmblem[i] == -1 || fNow < g_fNextAura[i])
		{
			continue;
		}

		// Staggered so a server full of emblems does not draw them all on the same tick.
		g_fNextAura[i] = fNow + 0.5 + GetRandomFloat(0.0, 0.15);

		DrawAura(i, g_iActiveEmblem[i]);
	}
}

void DrawAura(int iClient, int iItem)
{
	char sAura[16];
	float fFeet[3], fChest[3], fHead[3], fPoint[3], fHigh[3], fUp[3] = { 0.0, 0.0, 1.0 };
	int iColor[4], iCore[4], iDeep[4], iTint[4];

	strcopy(sAura, sizeof(sAura), g_Items[iItem].sAura);

	if (sAura[0] == '\0' || StrEqual(sAura, "none"))
	{
		return;
	}

	iColor[0] = g_Items[iItem].iBeamColor[0];
	iColor[1] = g_Items[iItem].iBeamColor[1];
	iColor[2] = g_Items[iItem].iBeamColor[2];
	iColor[3] = 255;

	Fx_Lighter(iColor, 0.6, iCore);
	Fx_Darker(iColor, 0.5, iDeep);

	GetClientAbsOrigin(iClient, fFeet);

	fChest = fFeet;
	fChest[2] += 40.0;

	fHead = fFeet;
	fHead[2] += 78.0;

	g_fAuraSpin[iClient] += 1.3;

	float fSpin = g_fAuraSpin[iClient];

	// How far the player moved since the last aura: trails need a little speed to show.
	float fMoved = GetVectorDistance(g_fAuraLast[iClient], fFeet);
	float fLast[3];

	fLast = g_fAuraLast[iClient];
	g_fAuraLast[iClient] = fFeet;

	if (StrEqual(sAura, "flames"))
	{
		// Flickering flames licking up around the body.
		for (int i = 0; i < 3; i++)
		{
			fPoint = fFeet;
			fPoint[0] += GetRandomFloat(-14.0, 14.0);
			fPoint[1] += GetRandomFloat(-14.0, 14.0);
			fPoint[2] += GetRandomFloat(10.0, 60.0);

			Fx_Glow(fPoint, g_iFxFlame, GetRandomFloat(0.2, 0.4), 0.5, 200);
		}

		Fx_Light(fChest, iColor, 90.0, 0.6, 4);
	} else if (StrEqual(sAura, "frost"))
	{
		// Snowflakes drifting down around the player and a frosty ring at their feet.
		for (int i = 0; i < 3; i++)
		{
			fPoint = fHead;
			fPoint[0] += GetRandomFloat(-30.0, 30.0);
			fPoint[1] += GetRandomFloat(-30.0, 30.0);
			fPoint[2] += GetRandomFloat(0.0, 20.0);

			Fx_Glow(fPoint, g_iFxGlow, GetRandomFloat(0.06, 0.12), 1.0, 230);
		}

		fPoint = fFeet;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 36.0, 38.0, g_iBmCrystal, 3.0, 0.6, 0.0, iCore);
	} else if (StrEqual(sAura, "drip"))
	{
		// Drops falling off the player, splashing into small ripples.
		for (int i = 0; i < 2; i++)
		{
			fPoint = fChest;
			fPoint[0] += GetRandomFloat(-16.0, 16.0);
			fPoint[1] += GetRandomFloat(-16.0, 16.0);

			fHigh = fPoint;
			fHigh[2] -= 18.0;

			Fx_Beam(fPoint, fHigh, g_iBmPhys, 2.0, 0.5, 0.4, 0.0, iColor);
		}

		fPoint = fFeet;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 4.0, 40.0, g_iBmPhys, 2.0, 0.6, 0.0, iColor);
	} else if (StrEqual(sAura, "sparks"))
	{
		// Electricity jumping across the body.
		fPoint = fChest;
		fPoint[0] += GetRandomFloat(-18.0, 18.0);
		fPoint[1] += GetRandomFloat(-18.0, 18.0);
		fPoint[2] += GetRandomFloat(-30.0, 30.0);

		fHigh = fChest;
		fHigh[0] += GetRandomFloat(-18.0, 18.0);
		fHigh[1] += GetRandomFloat(-18.0, 18.0);
		fHigh[2] += GetRandomFloat(-30.0, 30.0);

		Fx_Beam(fPoint, fHigh, g_iBmLightning, 3.0, 3.0, 0.2, 6.0, iCore, 0, 30);
		Fx_Sparks(fPoint, fUp, 1, 1);
	} else if (StrEqual(sAura, "thunder"))
	{
		// A small storm cloud overhead that now and then drops a spark.
		fPoint = fHead;
		fPoint[2] += 22.0;

		Fx_Glow(fPoint, g_iFxSteam, 0.5, 0.6, 120);

		if (GetRandomInt(0, 2) == 0)
		{
			Fx_Bolt(fPoint, fHead, 3, 6.0, g_iBmLightning, 2.0, 0.15, iCore);
		}
	} else if (StrEqual(sAura, "glint"))
	{
		// Facets of the gem catching the light around the player.
		for (int i = 0; i < 2; i++)
		{
			fPoint = fChest;
			fPoint[0] += GetRandomFloat(-20.0, 20.0);
			fPoint[1] += GetRandomFloat(-20.0, 20.0);
			fPoint[2] += GetRandomFloat(-20.0, 30.0);

			float fA[3], fB[3];

			fA = fPoint;
			fB = fPoint;
			fA[2] -= 5.0;
			fB[2] += 5.0;

			Fx_Beam(fA, fB, g_iBmLaser, 1.0, 1.0, 0.3, 0.0, iCore);

			fA = fPoint;
			fB = fPoint;
			fA[0] -= 5.0;
			fB[0] += 5.0;

			Fx_Beam(fA, fB, g_iBmLaser, 1.0, 1.0, 0.3, 0.0, iColor);
		}
	} else if (StrEqual(sAura, "prism"))
	{
		// Seven coloured lights circling the player.
		for (int i = 0; i < 4; i++)
		{
			float fTurn = fSpin + 6.2832 * i / 4.0;

			fPoint = fChest;
			fPoint[0] += Cosine(fTurn) * 26.0;
			fPoint[1] += Sine(fTurn) * 26.0;
			fPoint[2] += Sine(fTurn * 2.0) * 10.0;

			Fx_Hue(GetGameTime() * 120.0 + i * 90.0, iTint);
			Fx_Dot(fPoint, iTint, 4.0, 0.5);
		}
	} else if (StrEqual(sAura, "smoke"))
	{
		// Puffs of smoke curling up from the player's feet.
		fPoint = fFeet;
		fPoint[0] += GetRandomFloat(-10.0, 10.0);
		fPoint[1] += GetRandomFloat(-10.0, 10.0);
		fPoint[2] += 6.0;

		TE_SetupSmoke(fPoint, g_iFxSteam, GetRandomFloat(10.0, 18.0), 6);
		TE_SendToAll();

		Fx_Ring(fPoint, 20.0, 34.0, g_iBmPhys, 6.0, 0.6, 2.0, iDeep);
	} else if (StrEqual(sAura, "glitch"))
	{
		// Broken lines of colour flickering on and off around the player.
		for (int i = 0; i < 2; i++)
		{
			fPoint = fChest;
			fPoint[0] += GetRandomFloat(-24.0, 24.0);
			fPoint[1] += GetRandomFloat(-24.0, 24.0);
			fPoint[2] += GetRandomFloat(-36.0, 36.0);

			fHigh = fPoint;
			fHigh[0] += GetRandomFloat(-14.0, 14.0);
			fHigh[1] += GetRandomFloat(-14.0, 14.0);

			Fx_Beam(fPoint, fHigh, g_iBmXBeam, GetRandomFloat(2.0, 5.0), 2.0, GetRandomFloat(0.1, 0.25), 0.0, i ? iColor : iCore);
		}
	} else if (StrEqual(sAura, "speed"))
	{
		// Streaks left behind when running, in the emblem's colour.
		if (fMoved > 40.0)
		{
			for (int i = 0; i < 3; i++)
			{
				float fA[3], fB[3];

				fA = fLast;
				fB = fFeet;

				fA[2] += 12.0 + i * 24.0;
				fB[2] += 12.0 + i * 24.0;

				Fx_Beam(fA, fB, g_iBmPhys, 6.0 - i, 1.0, 0.4, 0.0, i == 1 ? iCore : iColor);
			}
		} else {
			Fx_Ring(fFeet, 10.0, 30.0, g_iBmPhys, 3.0, 0.4, 0.0, iColor);
		}
	} else if (StrEqual(sAura, "bolt"))
	{
		// Lightning: crackling yellow bolts trailing behind a running player.
		if (fMoved > 40.0)
		{
			fLast[2] += 36.0;

			fPoint = fFeet;
			fPoint[2] += 36.0;

			Fx_Bolt(fLast, fPoint, 3, 10.0, g_iBmLightning, 4.0, 0.3, iColor);
		}

		Fx_Sparks(fFeet, fUp, 1, 1);
	} else if (StrEqual(sAura, "dust"))
	{
		// Cheetah: dust kicked up by quick feet.
		if (fMoved > 20.0)
		{
			TE_SetupDust(fFeet, fUp, 16.0, 1.0);
			TE_SendToAll();
		}
	} else if (StrEqual(sAura, "float"))
	{
		// Gravity and falling emblems: slow rings rising up the body, as if the air was lifting.
		fPoint = fFeet;
		fPoint[2] += 4.0 + (RoundToFloor(fSpin) % 4) * 18.0;

		Fx_Ring(fPoint, 22.0, 30.0, g_iBmPhys, 3.0, 0.6, 0.0, iColor);
	} else if (StrEqual(sAura, "bounce"))
	{
		// Jump emblems: a springy pulse at the feet.
		fPoint = fFeet;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 4.0, 46.0, g_iBmLaser, 4.0, 0.35, 0.0, iColor);
		Fx_Ring(fPoint, 4.0, 26.0, g_iBmLaser, 2.0, 0.25, 0.0, iCore);
	} else if (StrEqual(sAura, "wisp"))
	{
		// Ghostly wisps drifting around the player.
		float fTurn = fSpin;

		fPoint = fChest;
		fPoint[0] += Cosine(fTurn) * 30.0;
		fPoint[1] += Sine(fTurn) * 30.0;
		fPoint[2] += Sine(fTurn * 0.7) * 20.0;

		Fx_Glow(fPoint, g_iFxSoftGlow, 0.25, 0.8, 120);
		Fx_Dot(fPoint, iColor, 3.0, 0.6);
	} else if (StrEqual(sAura, "halo"))
	{
		// A halo above the head, for the healing and protecting emblems.
		fPoint = fHead;
		fPoint[2] += 10.0;

		Fx_Ring(fPoint, 15.0, 16.0, g_iBmLaser, 3.0, 0.65, 0.0, iCore);
	} else if (StrEqual(sAura, "shield"))
	{
		// Armour and resistance: a ring of force around the body.
		Fx_Ring(fChest, 34.0, 36.0, g_iBmPhys, 10.0, 0.65, 0.0, iDeep);
		Fx_Ring(fFeet, 34.0, 36.0, g_iBmPhys, 4.0, 0.65, 0.0, iColor);
	} else if (StrEqual(sAura, "gold"))
	{
		// Precious metal glinting in the light.
		fPoint = fChest;
		fPoint[0] += GetRandomFloat(-18.0, 18.0);
		fPoint[1] += GetRandomFloat(-18.0, 18.0);
		fPoint[2] += GetRandomFloat(-20.0, 30.0);

		Fx_Glow(fPoint, g_iFxYellowGlow, 0.15, 0.4, 255);
		Fx_Dot(fPoint, iCore, 2.0, 0.4);
	} else if (StrEqual(sAura, "drain"))
	{
		// Dark threads being drawn into the player from around them.
		fPoint = fChest;
		fPoint[0] += GetRandomFloat(-60.0, 60.0);
		fPoint[1] += GetRandomFloat(-60.0, 60.0);
		fPoint[2] += GetRandomFloat(-30.0, 30.0);

		Fx_Beam(fPoint, fChest, g_iBmSpine, 3.0, 1.0, 0.4, 2.0, iColor);
	} else if (StrEqual(sAura, "demon"))
	{
		// Dark purple flames and a slow, heavy pulse at the feet.
		fPoint = fFeet;
		fPoint[2] += 30.0;

		Fx_Glow(fPoint, g_iFxPurpleGlow, 0.6, 0.6, 160);

		fPoint = fFeet;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 50.0, 10.0, g_iBmLaser, 6.0, 0.6, 0.0, iColor);
	} else if (StrEqual(sAura, "radiation"))
	{
		// Nuke: a sickly glow and a warning pulse.
		Fx_Ring(fChest, 10.0, 70.0, g_iBmPhys, 4.0, 0.5, 0.0, iColor);
		Fx_Light(fChest, iColor, 100.0, 0.6, 3);
	} else if (StrEqual(sAura, "vortex"))
	{
		// Portals: a little swirl of the other side, spinning around the player.
		for (int i = 0; i < 2; i++)
		{
			float fTurn = fSpin * 1.5 + 3.1416 * i;
			float fA[3], fB[3];

			fA = fChest;
			fB = fChest;

			fA[0] += Cosine(fTurn) * 26.0;
			fA[1] += Sine(fTurn) * 26.0;
			fB[0] += Cosine(fTurn + 1.2) * 16.0;
			fB[1] += Sine(fTurn + 1.2) * 16.0;
			fB[2] += 10.0;

			Fx_Beam(fA, fB, g_iBmPhys, 4.0, 1.0, 0.5, 0.0, i ? iCore : iColor);
		}
	} else if (StrEqual(sAura, "blink"))
	{
		// Warp: the player's outline flickers as if they could vanish any moment.
		Fx_Glow(fChest, g_iFxSoftGlow, 0.5, 0.15, 160);
		Fx_Ring(fChest, 30.0, 4.0, g_iBmLaser, 3.0, 0.25, 0.0, iColor);
	} else if (StrEqual(sAura, "sun"))
	{
		// Solar: a warm sun glow overhead.
		fPoint = fHead;
		fPoint[2] += 16.0;

		Fx_Glow(fPoint, g_iFxSoftGlow, 0.5, 0.6, 200);
		Fx_Light(fPoint, iColor, 120.0, 0.6, 4);
	} else if (StrEqual(sAura, "eclipse"))
	{
		// Eclipse: a dark disc overhead with a bright corona.
		fPoint = fHead;
		fPoint[2] += 16.0;

		Fx_Glow(fPoint, g_iFxBlackBall, 0.2, 0.6, 255);
		Fx_Ring(fPoint, 9.0, 11.0, g_iBmLaser, 2.0, 0.6, 1.0, iCore);
	} else if (StrEqual(sAura, "embers"))
	{
		// Chaos: embers floating up from the ground.
		for (int i = 0; i < 2; i++)
		{
			fPoint = fFeet;
			fPoint[0] += GetRandomFloat(-30.0, 30.0);
			fPoint[1] += GetRandomFloat(-30.0, 30.0);

			fHigh = fPoint;
			fHigh[2] += GetRandomFloat(30.0, 70.0);

			Fx_Beam(fPoint, fHigh, g_iBmLaser, 2.0, 0.5, 0.6, 0.0, iColor);
		}
	} else if (StrEqual(sAura, "confetti"))
	{
		// Party: confetti in every colour drifting down.
		for (int i = 0; i < 4; i++)
		{
			fPoint = fHead;
			fPoint[0] += GetRandomFloat(-36.0, 36.0);
			fPoint[1] += GetRandomFloat(-36.0, 36.0);
			fPoint[2] += GetRandomFloat(0.0, 24.0);

			Fx_Hue(GetRandomFloat(0.0, 360.0), iTint);
			Fx_Dot(fPoint, iTint, 3.0, 0.8);
		}
	} else if (StrEqual(sAura, "stars"))
	{
		// Midnight: tiny stars twinkling in a dark ring overhead.
		for (int i = 0; i < 3; i++)
		{
			float fTurn = fSpin * 0.4 + 6.2832 * i / 3.0;

			fPoint = fHead;
			fPoint[0] += Cosine(fTurn) * 22.0;
			fPoint[1] += Sine(fTurn) * 22.0;
			fPoint[2] += 12.0;

			Fx_Glow(fPoint, g_iFxGlow, 0.05, 0.6, 255);
		}

		Fx_Dot(fHead, iDeep, 6.0, 0.6);
	} else if (StrEqual(sAura, "rising"))
	{
		// Crimson and similar: sparks of colour rising off the body.
		fPoint = fChest;
		fPoint[0] += GetRandomFloat(-14.0, 14.0);
		fPoint[1] += GetRandomFloat(-14.0, 14.0);

		fHigh = fPoint;
		fHigh[2] += 50.0;

		Fx_Beam(fPoint, fHigh, g_iBmLaser, 2.0, 0.5, 0.5, 0.0, iColor);
		Fx_Dot(fHigh, iCore, 3.0, 0.4);
	} else if (StrEqual(sAura, "pulse"))
	{
		// Cyan and similar: a soft heartbeat ring around the chest.
		Fx_Ring(fChest, 10.0, 50.0, g_iBmLaser, 4.0, 0.5, 0.0, iColor);
	} else if (StrEqual(sAura, "dusk"))
	{
		// Sunset: two bands of colour, warm above and cool below.
		int iCool[4] = { 120, 60, 160, 255 };

		fPoint = fChest;
		fPoint[2] += 18.0;

		Fx_Ring(fPoint, 28.0, 30.0, g_iBmPhys, 6.0, 0.6, 0.0, iColor);

		fPoint[2] -= 36.0;

		Fx_Ring(fPoint, 28.0, 30.0, g_iBmPhys, 6.0, 0.6, 0.0, iCool);
	} else if (StrEqual(sAura, "code"))
	{
		// Matrix: green streaks raining down around the player.
		for (int i = 0; i < 3; i++)
		{
			fPoint = fHead;
			fPoint[0] += GetRandomFloat(-30.0, 30.0);
			fPoint[1] += GetRandomFloat(-30.0, 30.0);
			fPoint[2] += GetRandomFloat(0.0, 20.0);

			fHigh = fPoint;
			fHigh[2] -= GetRandomFloat(20.0, 50.0);

			Fx_Beam(fPoint, fHigh, g_iBmLaser, 1.5, 1.5, 0.4, 0.0, i ? iColor : iCore);
		}
	} else if (StrEqual(sAura, "crackle"))
	{
		// Phazon: unstable blue energy crackling over the skin.
		Fx_Bolt(fFeet, fHead, 4, 12.0, g_iBmShock, 4.0, 0.2, iColor);
	} else if (StrEqual(sAura, "haze"))
	{
		// 420: a slow green haze.
		fPoint = fHead;
		fPoint[0] += GetRandomFloat(-8.0, 8.0);
		fPoint[1] += GetRandomFloat(-8.0, 8.0);

		TE_SetupSmoke(fPoint, g_iFxSteam, 10.0, 4);
		TE_SendToAll();

		Fx_Dot(fPoint, iColor, 5.0, 0.6);
	} else if (StrEqual(sAura, "void"))
	{
		// Black: a ring of nothing that swallows the light.
		Fx_Ring(fFeet, 40.0, 10.0, g_iBmSpine, 8.0, 0.6, 0.0, iColor);
		Fx_Glow(fChest, g_iFxBlackBall, 0.15, 0.5, 200);
	} else if (StrEqual(sAura, "radiant"))
	{
		// White: a pure, steady glow.
		Fx_Glow(fChest, g_iFxSoftGlow, 0.7, 0.6, 140);
		Fx_Light(fChest, iColor, 80.0, 0.6, 3);
	} else if (StrEqual(sAura, "phase"))
	{
		// Phantom: a green shimmer slipping in and out of sight.
		fPoint = fChest;
		fPoint[2] += GetRandomFloat(-30.0, 30.0);

		Fx_Ring(fPoint, 20.0, 22.0, g_iBmPhys, 3.0, 0.3, 4.0, iColor);
	} else if (StrEqual(sAura, "heart"))
	{
		// Pink and Lifeline: soft rising glows.
		fPoint = fChest;
		fPoint[0] += GetRandomFloat(-12.0, 12.0);
		fPoint[1] += GetRandomFloat(-12.0, 12.0);
		fPoint[2] += 30.0;

		Fx_Glow(fPoint, g_iFxPurpleGlow, 0.2, 0.7, 200);
		Fx_Dot(fPoint, iColor, 4.0, 0.5);
	}

}
